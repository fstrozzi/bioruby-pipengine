module Bio
	module Pipengine
	
		def self.run(options)

			# reading the yaml files
			pipeline = YAML.load_file options[:pipeline]
			samples_file = YAML.load_file options[:samples_file]
			samples_file["samples"].each do |k,v|
				if v.kind_of? Hash
					samples_file["samples"][k] = Hash[samples_file["samples"][k].map{ |key, value| [key.to_s, value.to_s] }] 
				else
					samples_file["samples"][k] = v.to_s
				end
			end
			# make sure everything in Samples and Resources is converted to string
			#samples_file["samples"] = Hash[samples_file["samples"].map{ |key, value| [key.to_s, value.to_s] }] 
			samples_file["resources"] = Hash[samples_file["resources"].map {|k,v| [k.to_s, v.to_s]}]	
			
			# pre-running checks	
			check_steps(options[:steps],pipeline)	
			check_samples(options[:samples],samples_file) if options[:samples]

			# list of samples the jobs will work on
			samples_list = nil
			# check if a group is specified
			if options[:group]
				samples_list = options[:samples] ? samples_file["samples"][options[:group]].select {|k,v| options[:samples].include? k} : samples_file["samples"][options[:group]]
				options[:multi] = samples_list.keys 
				samples_file["resources"]["output"] << "/#{options[:group]}"	
			else # if not, proceed normalizing the sample list to remove groups and get a list of all samples
				full_list_samples = {}
				samples_file["samples"].each_key do |k| 
					if samples_file["samples"][k].kind_of? Hash
						full_list_samples.merge! samples_file["samples"][k]
					else
						full_list_samples[k] = samples_file["samples"][k]
					end
				end
				samples_list = options[:samples] ? full_list_samples.select {|k,v| options[:samples].include? k} : full_list_samples
			end
				
			########### START ###########

			# create output directory (jobs scripts will be saved there)
			FileUtils.mkdir_p samples_file["resources"]["output"] unless options[:dry] #&& options[:spooler]!="pbs"

			# check if the requested steps are multi-samples
			run_multi = check_and_run_multi(samples_file,pipeline,samples_list,options)
			
			unless run_multi # there are no multi-samples steps, so iterate on samples and create one job per sample
				samples_list.each_key do |sample_name|
					sample = Bio::Pipengine::Sample.new(sample_name,samples_list[sample_name])
					create_job(samples_file,pipeline,samples_list,options,sample)
				end
			end
		end

		# handle steps that run on multiple samples (i.e. sample groups job)
		def self.check_and_run_multi(samples_file,pipeline,samples_list,options)
			step_multi = options[:steps].map {|s| Bio::Pipengine::Step.new(s,pipeline["steps"][s]).is_multi?}
			
			if step_multi.include? false
				if step_multi.uniq.size > 1
					puts "\nAbort! You are trying to run both multi-samples and single sample steps in the same job".red
					exit
				else
					return false
				end
			else
				samples_obj = {}
				samples_list.each_key {|sample_name| samples_obj[sample_name] = Bio::Pipengine::Sample.new(sample_name,samples_list[sample_name])}
				create_job(samples_file,pipeline,samples_list,options,samples_obj)
				return true
			end
		end

		def self.create_job(samples_file,pipeline,samples_list,options,sample)
			# getting the sample name (only if this is not a multi samples job)
			sample_name = (sample.kind_of? Hash) ? nil : sample.name+"-"
			# setting the job name
			job_name = nil
			if options[:name] 
				job_name = options[:name]
			elsif options[:steps].size > 1
				job_name = "#{sample_name}#{options[:steps].join("-")}"
			else
				job_name = "#{sample_name}#{options[:steps].first}"
			end	
			# creating the Job object
			job = Bio::Pipengine::Job.new(job_name)
			job.local = options[:tmp]
			job.custom_output = options[:output_dir]
			job.custom_name = (options[:name]) ? options[:name] : nil
			job.add_resources pipeline["resources"]
			job.add_resources samples_file["resources"]
			#setting the logging system
			job.log = options[:log]
			job.log_adapter = options[:log_adapter]
			# setting sample groups either by cli option (if present) or by taking all available samples
			job.multi_samples = (options[:multi]) ? options[:multi] : samples_list.keys
			job.samples_obj = sample if sample.kind_of? Hash
			# cycling through steps and add command lines to the job
			options[:steps].each do |step_name| 
				# TODO WARNING this can add multiple times the same step is the are multi dependencies
				self.add_job(job, pipeline, step_name, sample)
			end

			if options[:dry] #&& options[:spooler] == "script"
				job.to_script(options)
			else
			  script = job.to_pbs(options) # converting the Job into a TORQUE::Qsub PBS compatible object
			  job_id = script.submit(options)
			  puts "#{job_id}".green unless options[:dry]
            end
		end

		# check if sample exists
		def self.check_samples(passed_samples,samples)
			passed_samples.each do |sample|
				samples_names = []
				samples["samples"].each_key do |k|
					if samples["samples"][k].kind_of? Hash
						samples["samples"][k].each_key {|s| samples_names << s}
					else
						samples_names << k
					end
				end
				unless samples_names.include? sample
					puts "Sample \"#{sample}\" does not exist in sample file!".red
					exit
				end
			end
		end

		# check if step exists
		def self.check_steps(passed_steps,pipeline)
			passed_steps.each do |step|
				unless pipeline["steps"].keys.include? step
					puts "Step \"#{step}\" does not exist in pipeline file!".red
					exit
				end
			end
		end

		# load the pipeline file and show a list of available steps
		def self.inspect_steps(pipeline_file)
			pipeline = YAML.load_file pipeline_file
			print "\nPipeline: ".blue 
			print "#{pipeline["pipeline"]}\n\n".green
			puts "List of available steps:".light_blue
			pipeline["steps"].each_key do |s|
				print "\s\s#{s}:\s\s".blue 
				print "#{pipeline["steps"][s]["desc"]}\n".green
			end
			puts "\n"
		end
		
		# create the samples.yml file (CASAVA ONLY!)
		def self.create_samples(dir)
				File.open("samples.yml","w") do |file|
					file.write "resources:\n\soutput: #{FileUtils.pwd}\n\nsamples:\n"
					samples = Hash.new {|hash,key| hash[key] = []}
					dir.each do |path|
						projects = Dir.glob(path+"/*").sort.select {|folders| folders.split("/")[-1] =~/Project_/}
						unless projects.empty?
							projects.each do |project_folder|
								Dir.glob(project_folder+"/*").sort.each {|s| samples[s.split("/")[-1]] << s}
							end
						else
							Dir.glob(path+"/*").sort.each {|s| samples[s.split("/")[-1]] << s if Dir.exists? s}
						end
					end
					samples.each_key do |sample|
						file.write "\s"+sample+":\s"+samples[sample].join(",")+"\n"	
					end
				end
		end

		# show running jobs information
		def self.show_stats(job_ids)
			stats = TORQUE::Qstat.new
			if job_ids.first == "all"
				stats.display
			else
				stats.display(:job_ids => job_ids)
			end
		end

		# delete running jobs from the scheduler
		def self.delete_jobs(job_ids)
			include TORQUE
			if job_ids == ["all"]
				Qdel.rm_all
			else 
				job_ids.each {|job_id| Qdel.rm job_id}
			end
		end #delete_jobs

		# check if required configuration exists
		def self.check_config
			unless File.exists?("#{Dir.home}/.torque_rm.yaml")
				ARGV.clear
				current_user = Etc.getlogin
				puts "\nIt seems you are running PipEngine for the first time. Please fill in the following information:"
				print "\nHostname or IP address of authorized server from where jobs will be submitted: ".light_blue
				server = gets.chomp
				print "\n"
				print "Specify the username you will be using to connect and submit jobs [#{current_user}]: ".light_blue
				username = gets.chomp
				username = (username == "") ? current_user : username
				puts "Attempting connection to the server...".green
				path = `ssh #{username}@#{server} -t "which qsub"`.split("/qsub").first
				unless path=~/\/\S+\/\S+/
					warn "Connection problems detected! Please check that you are able to connect to '#{server}' as '#{username}' via ssh.".red
				else	
					file = File.open("#{Dir.home}/.torque_rm.yaml","w")
					file.write({:hostname => server, :path => path, :user => username}.to_yaml)
					file.close
					puts "First time configuration completed!".green
					puts "It is strongly recommended to setup a password-less SSH connection to use PipEngine.".green
					exit
				end
			end
		end #check_config

		def self.add_job(job, pipeline, step_name, sample)
			step = Bio::Pipengine::Step.new(step_name,pipeline["steps"][step_name]) # parsing step instructions
			self.add_job(job, pipeline, step.pre, sample) if step.has_prerequisite?
			job.add_step(step,sample) # adding step command lines to the job	
		end #add_job
		
	end
end
