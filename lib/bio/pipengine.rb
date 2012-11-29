module Bio
	module Pipengine

		def self.create_pipeline(file)
			pipeline = YAML.load_file(file)
			rake = File.open(pipeline["pipeline"]+".rake","w")
			pipeline["step"].each_key do |k|
				rake.write "desc \"Run #{k}"
				if pipeline["step"][k]["threads"]
					rake.write " (#{pipeline["step"][k]["threads"]} CPU)\"\n" 
				else
					rake.write "\"\n"
				end
				rake.write create_task(k,pipeline)
			end
			rake.close
		end

		def self.create_task(step_name,pipeline)
			"task :#{step_name} do\n#{process_cmd_line(pipeline["step"][step_name]["run"],pipeline)}end\n\n"
		end

		def self.process_cmd_line(run,pipeline)
			cmd_line = ""
			if run.kind_of? Array
				run.each {|cmd| cmd_line << "\tsh \""+sub_fields(cmd,pipeline)+"\"\n" }
			else
				cmd_line << "\tsh \""+sub_fields(run,pipeline)+"\"\n"
			end
			cmd_line
		end

		def self.sub_fields(cmd,pipeline)
			pipeline["resources"].each_key {|r| cmd.gsub!("<#{r}>",pipeline["resources"][r])}
			cmd.gsub!('<pipeline>',pipeline["pipeline"])
			cmd.gsub!('<sample>','#{ENV["sample"]}')
			cmd.gsub!('<sample_path>','#{ENV["sample_path"}')
			cmd
		end

	end
end
