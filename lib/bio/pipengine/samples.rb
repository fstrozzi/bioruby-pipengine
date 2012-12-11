module Bio
	module Pipengine
		module Samples
				
			def self.create_samples(sample_dir)
					File.open("samples.yml","w") do |file|
						file.write "resources:\n\soutput:\n\nsamples:\n"
						Dir.glob(sample_dir+"/*").each do |sample|
							file.write "\s"+sample.split("/")[-1]+": "+sample+"\n"	
						end
					end
			end
		end
	end
end

