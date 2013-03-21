module Bio
	module Pipengine

		def self.run(options)

      pipeline = YAML.load_file options[:pipeline]
			samples = YAML.load_file options[:samples_file]
      samples["samples"] = Hash[samples["samples"].map{ |k, v| [k.to_s, v] }]
			samples_list = options[:samples] ? samples["samples"].select {|k,v| options[:samples].include? k} : samples["samples"]

			samples_list.each_key do |sample|
				job_opts = {job_name:[], step:[], cpu:[]}
				cmd = []
				options[:steps].each do |step|
					specs = pipeline["step"][step]

          if specs.nil?
						puts "No step #{step} found in #{options[:pipeline]}"
						exit
					end

          if specs["groups"]
						options[:groups] ||= samples["samples"].keys
						job_opts[:groups] = true
					end

          if specs["run"].kind_of? Array
            	specs["run"].each {|run| cmd << sub_fields(run,pipeline,sample,samples,job_opts[:output],options[:groups],step) }
          else
            	cmd << sub_fields(specs["run"],pipeline,sample,samples,job_opts[:output],options[:groups],step)
          end
					job_opts[:cpu] << (specs["cpu"] ||= 1)

          if options[:local]
						job_opts[:output] = options[:local]
					elsif options[:groups]
						job_opts[:output] = samples["resources"]["output"]
					else
						job_opts[:output] = samples["resources"]["output"] + "/"+sample
					end

          job_opts[:step] << step
					job_opts[:local] = options[:local]
					job_opts[:dry] = options[:dry]

        end

				if options[:name]
					job_opts[:job_name] = generate_uuid+"-"+options[:name]
					job_opts[:step] = options[:name]
				else
					job_opts[:job_name] = generate_uuid+"-"+job_opts[:step].join("-")
					job_opts[:step] = job_opts[:step].join("-")
				end
				job_opts[:cpu] = job_opts[:cpu].max
				run_job cmd.join("\n"),job_opts,samples,sample
				break if options[:groups]
			end
			
		end

		def self.run_job(cmd,opts,samples,sample)
			File.open(opts[:job_name]+"_job.sh","w") do |file|
				file.write "#!/bin/bash\n#PBS -N #{opts[:job_name]}\n#PBS -l ncpus=#{opts[:cpu]}\n\n"
				if opts[:local]
					file.write "mkdir -p #{opts[:output]+"/"+opts[:job_name]}\ncd #{opts[:output]+"/"+opts[:job_name]}\n"
				else
					file.write "mkdir -p #{opts[:output]}/#{opts[:step]}\ncd #{opts[:output]}/#{opts[:step]}\n"
				end
				file.write cmd+"\n"
				if opts[:groups] && opts[:local]
					file.write "mkdir -p #{samples["resources"]["output"]}/#{opts[:step]}\n"
					file.write "cp -r #{opts[:output]+"/"+opts[:job_name]}/* #{samples["resources"]["output"]}/#{opts[:step]}\n"
					file.write "rm -fr #{opts[:output]+"/"+opts[:job_name]}\n"
				elsif opts[:local]
					file.write "mkdir -p #{samples["resources"]["output"]}/#{sample}/#{opts[:step]}\n"
					file.write "cp -r #{opts[:output]+"/"+opts[:job_name]}/* #{samples["resources"]["output"]}/#{sample}/#{opts[:step]}\n"
					file.write "rm -fr #{opts[:output]+"/"+opts[:job_name]}\n"
				end
			end
			system "qsub #{opts[:job_name]}_job.sh" unless opts[:dry]
		end

		def self.sub_fields(command,pipeline,sample,samples,output,groups,step)
			command_line = command
			pipeline["resources"].each_key {|r| command_line.gsub!("<#{r}>",pipeline["resources"][r])}
			samples["resources"].each_key {|r| command_line.gsub!("<#{r}>",samples["resources"][r])}
			command_line = command_line.gsub('<pipeline>',pipeline["pipeline"])	
      command_line = set_groups(command_line,pipeline,groups,samples,step) if groups
			command_line = sub_placeholders(command_line,sample,samples)
			command_line
		end

		def self.generate_uuid
			UUID.new.generate.split("-").first
		end

		def self.set_groups(command_line,pipeline,groups,samples,step)
			group_cmd = pipeline["step"][step]["groups"]
			if group_cmd.kind_of? Array
				group_cmd.each_with_index do |g,index|
					list = sub_groups(groups,g,samples)
					command_line = command_line.gsub("<groups#{index+1}>",list.join("\s"))
				end
			else
				list = sub_groups(groups,group_cmd,samples)
				command_line = command_line.gsub("<groups>",list.join("\s"))
			end
			command_line
		end

		def self.sub_groups(groups,group_cmd,samples)
			list = groups.map do |g|
				if g.include? ','
					g.split(',').map {|sample| sub_placeholders(group_cmd,sample,samples)}.join(',')
				else
					sub_placeholders(group_cmd,g,samples)
				end
			end
			list
		end

		def self.sub_placeholders(command_line,sample,samples)
			check_sample sample,samples
			sample_path = samples["samples"][sample]
			command_line.scan(/<(\S+)\/sample>/).map {|e| e.first}.each do |input_folder|
      	if Dir.exists? samples["resources"]["output"]+"/"+sample+"/"+input_folder
      		command_line = command_line.gsub(/<#{input_folder}\/sample>/,samples["resources"]["output"]+"/"+sample+"/"+input_folder+"/"+sample)
      	else
        	warn "Warning: Directory "+samples["resources"]["output"]+"/"+sample+"/"+input_folder+" not found. Assuming input will be in the CWD"
        	command_line = command_line.gsub(/<#{input_folder}\/sample>/,sample)
      	end
			end
      command_line = command_line.gsub('<sample>',sample)
      command_line = command_line.gsub('<sample_path>',sample_path)
      command_line = command_line.gsub('<output>',samples["resources"]["output"])
			command_line	
		end

		def self.check_sample(sample,samples)
			unless samples["samples"].include? sample
				puts "No sample #{sample} found in samples file!"	
				exit
			end
		end
	end
end
