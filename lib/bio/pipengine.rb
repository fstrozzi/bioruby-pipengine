module Bio
	module Pipengine

		def self.run(options)

			# reading the yaml files
			pipeline = YAML.load_file options[:pipeline]
			samples_file = YAML.load_file options[:samples_file]
      samples_file["samples"] = Hash[samples_file["samples"].map{ |k, v| [k.to_s, v] }]
		
			# pre-running checks	
			check_samples(options[:samples],samples_file) if options[:samples]
			check_steps(options[:steps],pipeline)
			
			########### START ###########

			# list of samples the jobs will work on
			samples_list = options[:samples] ? samples_file["samples"].select {|k,v| options[:samples].include? k} : samples_file["samples"]	
		
			# check if the requested steps are multi-samples
			run_group = check_and_run_groups(samples_file,pipeline,samples_list,options)
			
			unless run_group # there are no multi-sample steps, so iterate on samples and create one job per sample
				samples_list.each_key do |sample_name|
					sample = Bio::Pipengine::Sample.new(sample_name,samples_list[sample_name])
					create_job(samples_file,pipeline,samples_list,options,sample)
				end
			end
		end

		# handle steps that run on multiple samples (i.e. sample groups job)
		def self.check_and_run_groups(samples_file,pipeline,samples_list,options)
			step_groups = options[:steps].map {|s| Bio::Pipengine::Step.new(s,pipeline["steps"][s]).is_group?}
			if step_groups.include? false
				if step_groups.size > 1
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
			# setting the job name
			job_name = nil
			if options[:name] 
				job_name = options[:name]
			elsif options[:steps].size > 1
				job_name = options[:steps].join("-")
			else
				job_name = options[:steps].first
			end			
			# creating the Job object
			job = Bio::Pipengine::Job.new(job_name)
			job.local = options[:local]
			job.add_resources pipeline["resources"]
			job.add_resources samples_file["resources"]
			# setting sample groups either by cli option (if any) or by taking all available samples
			job.samples_groups = (options[:groups]) ? options[:groups] : samples_list.keys
			job.samples_obj = sample if sample.kind_of? Hash
			# cycling through steps and add command lines to the job
			options[:steps].each do |step_name|
				step = Bio::Pipengine::Step.new(step_name,pipeline["steps"][step_name]) # parsing step instructions
				job.add_step(step,sample) # adding step command lines to the job	
			end
			script = job.to_pbs(options) # converting the Job into a TORQUE::Qsub PBS compatible object
			job_id = script.submit(options)
			puts "#{job_id}".green unless options[:dry]
			#system("qsub #{script}") unless options[:dry] # submitting the job to the scheduler	
		end

		# check if sample exists
		def self.check_samples(passed_samples,samples)
			passed_samples.each do |sample|
				unless samples["samples"].keys.include? sample
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
		# create the samples.yml file

		def self.create_samples(sample_dirs)
				File.open("samples.yml","w") do |file|
					file.write "resources:\n\soutput:\n\nsamples:\n"
					samples = Hash.new {|hash,key| hash[key] = []}
					sample_dirs.each do |path|
						Dir.glob(path+"/*").each {|s| samples[s.split("/")[-1]] << s}
					end
					samples.each_key do |sample|
						file.write "\s"+sample+":\s"+samples[sample].join(",")+"\n"	
					end
				end
		end

		def self.show_stats(job_ids)
			stats = TORQUE::Qstat.new
			info = nil
			if job_ids.first == "all"
				info = stats.query
			else
				info = stats.query :job_ids => job_ids
			end
			print_jobs_table info
		end

	private
		
		def self.print_jobs_table(jobs_info)	
			rows = []
			head = ["Job ID","Job Name","Node","Mem Used","Run Time","Queue","Status"]
			head.map! {|h| h.light_red}
			if jobs_info == ""
				print "\n\nNo Running jobs for user: ".light_red+"#{`whoami`}".green+"\n\n"
				exit
			else
				jobs_info.each do |j|
					mem = (j[:resources_used_mem]) ? (j[:resources_used_mem].split("kb").first.to_f/1000).round(1) : "0"
					time = (j[:total_runtime]) ? j[:total_runtime].to_f.round(2).to_s : "0"
					node = (j[:exec_host]) ? j[:exec_host].split(".").first : "-" 
					line = [j[:job_id].split(".").first,j[:job_name],node,"#{mem} mb","#{time} sec.",j[:queue],j[:job_state]]
					case j[:job_state]
						when "C" then line[-1] = "Completed"; rows << line.map {|l| l.white.on_black.underline}
						when "Q" then line[-1] = "Queued"; rows << line.map {|l| l.light_blue}
						when "R" then line[-1] = "Running"; rows << line.map {|l| l.green}
						when "E" then line[-1] = "Exiting"; rows << line.map {|l| l.green.blink}
					end
				end
				print "\nSummary of submitted jobs for user: ".blue+"#{jobs_info.first[:job_owner].split("@").first.green}\n\n"
				table = Terminal::Table.new :headings => head, :rows => rows
				puts table
			end

		end

	end
end
