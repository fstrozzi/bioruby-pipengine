module Bio
	module Pipengine
		class Sample
			# Sample holds all the information on a sample and its original input path (or multiple paths)	
			attr_accessor :path
				def initialize(name,path_string,group)
					@path = path_string.split(",")
					@name = name
					@group = group
				end

				def name=(name)
					@name
				end

				def group=(group)
					@group
				end

				def group
					@group
				end

				def x_name
					"#{@group}/#{@name}"
				end

				def name
					@name
				end
		end
	end
end

