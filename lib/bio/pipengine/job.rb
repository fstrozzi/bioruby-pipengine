module Bio
	module Pipengine
		
		class Job
			
			# a Job object holds information on a job to be submitted
			# samples_groups and samples_obj are used to store information in case of steps that require to combine info
			# from multiple samples
			attr_accessor :name, :cpus, :nodes, :mem, :resources, :command_line, :local,
			              :multi_samples, :samples_obj, :custom_output, :custom_name,
			              :log, :log_adapter
			def initialize(name)
				@name = generate_uuid + "-" + name
				@shortname = name
				@command_line = []
				@resources = {}
				@cpus = 1
				@nodes = "1"
				@log = "stdin"
				@log_adapter = nil
			end

			def add_resources(resources)
				self.resources.merge! resources
			end

			def output
				self.resources["output"]
			end

			# add all the command lines for a given step
			def add_step(step,sample)	

				# setting job working directory
				working_dir = ""	
				if self.local 
					working_dir = self.local+"/"+self.name
				else
					working_dir = self.output

					if step.is_multi?	
						folder = (self.custom_output) ? self.custom_output : @shortname 
						working_dir += "/#{folder}"
					else
						folder =
						if self.custom_output 
							self.custom_output
						elsif self.custom_name
							self.custom_name
						else
							step.name
						end
						working_dir += "/#{sample.name}/#{folder}"
					end

				end

				# set job cpus number to the higher step cpus (this in case of multiple steps)
				self.cpus = step.cpus if step.cpus > self.cpus
				
				# set number of nodes for job
				self.nodes = (step.nodes) ? step.nodes : @nodes

				# set the memory used
				self.mem = step.mem

				# adding job working directory
				unless step.name.start_with? "_"
					self.command_line << "if [ ! -f #{working_dir}/checkpoint ]"
					self.command_line << "then"
					self.command_line << logger(step, "start")
					self.command_line << "\nmkdir -p #{working_dir}"
					self.command_line << "cd #{working_dir}"
				end

				# generate command lines for this step
				if step.run.kind_of? Array
					step.run.each_with_index do |cmd, i|
						command = generate_cmd_line(cmd,sample,step)
						# TODO verify that logger works in this case
						# self.command_line << "#{command} || { echo \"FAILED `date`: #{step.name}:#{i}\" ; exit 1; }"
						self.command_line << "#{command} || { #{logger(step, "Failed #{i}" )}; exit 1; }"
					end
				else
					command = generate_cmd_line(step.run,sample,step)
					# TODO verify that logger works in this case
					# self.command_line << "#{command} || { echo \"FAILED `date`: #{step.name} \" ; exit 1; }"
					self.command_line << "#{command} || { #{logger(step, "Failed" )}; exit 1; }"
				end
				self.command_line << logger(step, "finished")
                self.command_line << "touch #{working_dir}/checkpoint"
				self.command_line << "else"
				self.command_line << logger(step, "already executed, skip this step")
				self.command_line << "fi"
			
				# check if a temporary (i.e. different from 'output') directory is set
				if self.local
					final_output = ""

					if step.is_multi?	
						folder = (self.custom_output) ? self.custom_output : @shortname 
						final_output = self.output+"/#{folder}"	 
					else
						folder = (self.custom_output) ? self.custom_output : step.name
						final_output = self.output+"/#{sample.name}/#{folder}"
					end

					self.command_line << "mkdir -p #{final_output}"
					self.command_line << "cp -r #{working_dir}/* #{final_output}"
					self.command_line << "rm -fr #{working_dir}"
				end

			end

			# convert the job object into a TORQUE::Qsub object
			def to_pbs(options)
				TORQUE::Qsub.new(options) do |torque_job|
					torque_job.name = self.name
					torque_job.working_directory = self.output # where pbs scripts and stdout / stderr files will be saved
					if options[:pbs_opts] 
						torque_job.l = options[:pbs_opts]
					else
						l_string = []
						l_string << "nodes=#{self.nodes}:ppn=#{self.cpus}"
						l_string << "mem=#{self.mem}" if self.mem
						torque_job.l = l_string
						if options[:mail_exit]
							torque_job.m = "e"
							torque_job.M = options[:mail_exit]
						end
						if options[:mail_start]
							torque_job.m = "b"
							torque_job.M = options[:mail_start]
						end
					end
					
					torque_job.q = options[:pbs_queue] if options[:pbs_queue]

					torque_job.script = self.command_line.join("\n")+"\n"
                end
			end

			def to_script(options)
			  File.open(self.name+'.sh','w') do |file|
		          file.puts "#!/usr/bin/env bash -l"
			      file.puts self.command_line.join("\n")
			  end
			end

		private
			
			# create a unique ID for each job
			def generate_uuid
				SecureRandom.hex(5)
			end
			
			# this method call other methods to perform the right substitutions into the command lines
			def generate_cmd_line(cmd,sample,step)
				if step.is_multi? # if is a multi samples step call a different method
					set_multi_cmd(step,self.multi_samples)
					cmd = sub_multi(cmd,step)
				else
					cmd = sub_placeholders(cmd,sample,step) # normal step, perform usual substitutions
				end
				return cmd
			end
		
			# perform substitutions on all the placeholders
			def sub_placeholders(cmd,sample,step=nil)	
				tmp_cmd = cmd.gsub(/<sample>/,sample.name)
				if tmp_cmd =~/<sample_path>/
					sample_path_glob = (tmp_cmd.scan(/<sample_path>(\S+)/).map {|e| e.first})
					if sample_path_glob.empty?
						tmp_cmd.gsub!(/<sample_path>/,sample.path.join("\s"))
					else
						sample_path_glob.each do |append|
							tmp_cmd.gsub!(/<sample_path>#{Regexp.quote(append)}/,(sample.path.map {|s| s+append}).join("\s"))
						end
					end
				end
				# for resourcers and cpus
				tmp_cmd = sub_resources_and_cpu(tmp_cmd,step)
				
				# for placeholders like <mapping/sample>
				tmp_cmd.scan(/<(\S+)\/sample>/).map {|e| e.first}.each do |input_folder|
					warn "Directory #{self.output+"/"+sample.name+"/"+input_folder} not found".magenta unless Dir.exists? self.output+"/"+sample.name+"/"+input_folder
					tmp_cmd = tmp_cmd.gsub(/<#{input_folder}\/sample>/,self.output+"/"+sample.name+"/"+input_folder+"/"+sample.name)
				end
				
				# for placeholders like <mapping/>
				tmp_cmd.scan(/<(\S+)\/>/).map {|e| e.first}.each do |input_folder|
					warn "Directory #{self.output+"/"+sample.name+"/"+input_folder} not found".magenta unless Dir.exists? self.output+"/"+sample.name+"/"+input_folder
					tmp_cmd = tmp_cmd.gsub(/<#{input_folder}\/>/,self.output+"/"+sample.name+"/"+input_folder+"/")
				end
				return tmp_cmd
			end

			def sub_resources_and_cpu(cmd,step)	
				# for all resources tags like <gtf> <index> <genome> <bwa> etc.
				self.resources.each_key do |r|
					cmd.gsub!(/<#{r}>/,self.resources[r])
				end
				# set number of cpus for this command line
				cmd.gsub!(/<cpu>/,step.cpus.to_s) unless step.nil?
				return cmd
			end
	

			# creates actual multi-samples command lines to be substituted where <multi> placeholders are found
			def set_multi_cmd(step,multi_samples)
				if step.multi_def.kind_of? Array # in case of many multi-samples command lines
					step.multi_cmd = []
					step.multi_def.each do |m_def|
						step.multi_cmd << generate_multi_cmd(m_def,multi_samples)
					end
				else
					step.multi_cmd = generate_multi_cmd(step.multi_def,multi_samples)
				end
			end

			# take the multi_cmd and perform the subsitutions into the step command lines
			def sub_multi(cmd,step)
				cmd = sub_resources_and_cpu(cmd,step)
				if step.multi_cmd.kind_of? Array
					step.multi_cmd.each_with_index do |m,index|
						cmd.gsub!(/<multi#{index+1}>/,m)
					end
				else
					cmd.gsub!(/<multi>/,step.multi_cmd)
				end
				return cmd
			end

			# this sub method handle different multi-samples definitions (like comma separated list, space separated etc.)
			def generate_multi_cmd(multi_def,multi_samples)
				multi_cmd = []	
				multi_samples.each do |sample_name|
					if sample_name.include? ","
						multi_cmd << split_and_sub(",",multi_def,sample_name)
					elsif sample_name.include? ";"
						multi_cmd << split_and_sub(";",multi_def,sample_name)
					else
						multi_cmd << sub_placeholders(multi_def,self.samples_obj[sample_name])
					end
				end
				return multi_cmd.join("\s")
			end

			# take a non-space separated list of samples and perform the substitution with the group defitions
			def split_and_sub(sep,multi_def,multi)	
				cmd_line = []
				multi.split(sep).each do |sample_name|
					cmd_line << sub_placeholders(multi_def,self.samples_obj[sample_name])
				end
				cmd_line.join(sep)
			end

			# log a step according to the selected adapter
			def logger(step, message)  
				case self.log
					when "stdin"
					   "echo \"#{step.name} #{name} #{message} `whoami` `hostname` `pwd` `date`.\""
					when "syslog"
						 "logger -t PIPENGINE \"#{step.name} #{name} #{message} `whoami` `hostname` `pwd`\""
					when "fluentd"
						 "curl -X POST -d 'json={\"source\":\"PIPENGINE\", \"step\":\"#{step.name}\", \"message\":\"#{message}\", \"job_id\":\"#{name}\", \"user\":\"'"`whoami`"'\", \"host\":\"'"`hostname`"'\", \"pwd\":\"'"`pwd`"'\"}' #{self.log_adapter}"
					end
			end #logger

		end
	end
end

