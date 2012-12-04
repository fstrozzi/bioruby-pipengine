module Bio
	module Pipengine

		def self.run(options)
			pipeline = YAML.load_file options[:pipeline]
			samples = YAML.load_file options[:samples_file]
			job_opts = {job_name:[], step:[]}
			cmd = []
			options[:samples].each do |sample|
				options[:steps].each do |step|
					specs = pipeline["step"][step]
					if specs["multi"]
						# handle multi-sample steps
					else	
						job_opts[:cpus] = specs["threads"] ? specs["threads"] : 1
						job_opts[:output] = options[:local] ? options[:local] : samples["resources"]["output"]+"/"+sample
						job_opts[:step] << step
						job_opts[:local] = options[:local]
						job_opts[:dry] = options[:dry]
						if specs["run"].kind_of? Array
							specs["run"].each {|run| cmd << sub_fields(run,pipeline,sample,samples,job_opts[:output]) }
						else
							cmd << sub_fields(specs["run"],pipeline,sample,samples,job_opts[:output])
						end
					end
				end
				job_opts[:job_name] = generate_uuid+"-"+job_opts[:step].join("-")
				job_opts[:step] = job_opts[:step].join("-")
				run_job cmd.join("\n"),job_opts,samples,sample
			end
			
		end

		def self.run_job(cmd,opts,samples,sample)
			File.open(opts[:job_name]+"_job.sh","w") do |file|
				file.write "#!/bin/bash\n#PBS -N #{opts[:job_name]}\n#PBS -l ncpus=#{opts[:cpus]}\n\n"
				if opts[:local]
					file.write "mkdir -p #{opts[:output]+"/"+opts[:job_name]}\ncd #{opts[:output]+"/"+opts[:job_name]}\n"
				else
					file.write "mkdir -p #{samples["resources"]["output"]+"/"+sample}/#{opts[:step]}\ncd #{samples["resources"]["output"]+"/"+sample}/#{opts[:step]}\n"
				end
				file.write cmd+"\n"
				file.write "mkdir -p #{samples["resources"]["output"]}/#{sample}/#{opts[:step]}\n" if opts[:local]
				file.write "cp -r #{opts[:output]+"/"+opts[:job_name]}/* #{samples["resources"]["output"]}/#{sample}/#{opts[:step]}\n" if opts[:local]
				file.write "rm -fr #{opts[:output]+"/"+opts[:job_name]}\n" if opts[:local]
			end
			system "qsub job.sh" unless opts[:dry]
		end

		def self.sub_fields(command,pipeline,sample,samples,output)
			sample_path = samples[sample]
			pipeline["resources"].each_key {|r| command.gsub!("<#{r}>",pipeline["resources"][r])}
			samples["resources"].each_key {|r| command.gsub!("<#{r}>",samples["resources"][r])}
			command.gsub!('<pipeline>',pipeline["pipeline"])
			command.scan(/<(\S+)\/sample>/).map {|e| e.first}.each do |input_folder|
				 #if Dir.exists? samples["resources"]["output"]+"/#{input_folder}"
					command.gsub!(/<#{input_folder}\/sample>/,samples["resources"]["output"]+"/"+sample+"/"+input_folder+"/"+sample)
				 #end
			end
			command.gsub!('<sample>',sample)
			command.gsub!('<sample_path>',sample_path)
			command.gsub!('<output>',output)
			command
		end

		def self.generate_uuid
			UUID.new.generate.split("-").first
		end

	end
end
