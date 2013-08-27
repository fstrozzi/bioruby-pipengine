module Bio
	module Pipengine
		class Sample
			# Sample holds all the information on a sample and its original input path (or multiple paths)	
			attr_accessor :path, :name
				def initialize(name,path_string)
					@path = path_string.split(",")
					@name = name 
				end
		end
	end
end

