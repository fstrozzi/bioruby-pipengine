module Bio
	module Pipengine

		def self.run(options)
      
			# reading the yaml files

			pipeline = YAML.load_file options[:pipeline]
			samples_file = YAML.load_file options[:samples_file]
      samples_file["samples"] = Hash[samples_file["samples"].map{ |k, v| [k.to_s, v] }]
		
			# pre-runinng checks	
			check_samples(options[:samples],samples_file) if options[:samples]
			check_steps(options[:steps],pipeline)
			
			if options[:inspect_steps]
				inspect_steps(pipeline)
				exit
			end
			
			########### START ###########

			# list of samples the jobs will work on
			samples_list = options[:samples] ? samples_file["samples"].select {|k,v| options[:samples].include? k} : samples_file["samples"]	
			
			# steps that run on multiple samples will go alone (i.e. no multi steps job)
			if options[:steps].size == 1
				step = Bio::Pipengine::Step.new(options[:steps].first,pipeline["step"][options[:steps].first])
				if step.is_group?
					samples_obj = {}
					samples_list.each_key {|sample_name| samples_obj[sample_name] = Bio::Pipengine::Sample.new(sample_name,samples_list[sample_name])}
					create_job(samples_file,pipeline,samples_list,options,samples_obj)
				end
			else # its a normal step, so iterate on samples and create one job per sample
				samples_list.each_key do |sample_name|
					sample = Bio::Pipengine::Sample.new(sample_name,samples_list[sample_name])
					create_job(samples_file,pipeline,samples_list,options,sample)
				end
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
				step = Bio::Pipengine::Step.new(step_name,pipeline["step"][step_name]) # parsing step instructions
				job.add_step(step,sample) # adding step command lines to the job	
			end
			script = job.to_pbs(options) # converting the Job into a PBS compatible script
			system("qsub #{script}") unless options[:dry] # submitting the job to the scheduler	
		end

		# check if sample exists
		def self.check_samples(passed_samples,samples)
			passed_samples.each do |sample|
				unless samples["samples"].keys.include? sample
					puts "Sample \"#{sample}\" do not exist in sample file!"
					exit
				end
			end
		end

		# check if step exists
		def self.check_steps(passed_steps,pipeline)
			passed_steps.each do |step|
				unless pipeline["step"].keys.include? step
					puts "Step \"#{step}\" do not exist in pipeline file!"
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
			pipeline["step"].each_key do |s|
				print "\s\s#{s}:\s\s".blue 
				print "#{pipeline["step"][s]["desc"]}\n".green
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

	end
end
