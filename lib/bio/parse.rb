module Bio
	module Pipengine
		
		def parse(file)
			YAML.load_file(file)
		end

	end
end
