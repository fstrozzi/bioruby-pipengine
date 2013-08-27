module Bio
	module Pipengine

		class Step
			attr_accessor :name, :run, :cpus, :groups_def, :groups_cmd
			def initialize(name,step_instructions)
				@name = name
				parse_yaml(step_instructions)	
			end

			def is_group?
				return (self.groups_def.nil?) ? false : true
			end

			private

			def parse_yaml(step_instructions)
				self.cpus = step_instructions["cpu"].to_i
				self.run = step_instructions["run"]
				self.groups_def = step_instructions["groups"]
			end

		end

	end
end

