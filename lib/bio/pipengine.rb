module Bio
	module Pipengine

		def self.run(options)

      pipeline = YAML.load_file options[:pipeline]
			samples = YAML.load_file options[:samples_file]
      samples["samples"] = Hash[samples["samples"].map{ |k, v| [k.to_s, v] }]
			samples_list = options[:samples] ? samples["samples"].select {|k,v| options[:samples].include? k} : samples["samples"]
			samples_list.each_key do |sample|
			
			end
		end

		def self.generate_uuid
			UUID.new.generate.split("-").first
		end

		def self.check_sample(sample,samples)
			unless samples["samples"].include? sample
				puts "No sample #{sample} found in samples file!"	
				exit
			end
		end

		def self.create_samples(sample_dirs)
				File.open("samples.yml","w") do |file|
					file.write "resources:\n\soutput:\n\nsamples:\n"
					samples = Hash.new {|hash,key| hash[key] = []}
					sample_dirs.each do |path|
						Dir.glob(path+"/*").each {|s| samples[s.split("/")[-1]] << s}
					end
					samples.each_key do |sample|
						file.write "\s"+sample+":\s"+samples[sample].join(",")+"\n"	
					end
				end
		end

	end
end
