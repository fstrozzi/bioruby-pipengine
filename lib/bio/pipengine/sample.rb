module Bio
	module Pipengine
		class Sample
				attr_accessor :path, :name
				def initialize(name,path_string)
					@path = path_string.split(",")
					@name = name 
				end
		end
	end
end

