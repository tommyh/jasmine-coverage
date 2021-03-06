# This file holds the monkeypatches to open up jasmine headless for jasmine coverage.


# This patch writes out a copy of the file that was loaded into the JSCoverage context for testing.
# You can look at it to see if it included all the files and tests you expect.
require 'jasmine/headless/template_writer'
module Jasmine::Headless
  class TemplateWriter
    alias old_write :write

    def write
      ret = old_write
      str = File.open(all_tests_filename, "rb").read

      test_rigfolder = Jasmine::Coverage.output_dir+"/test-rig"
      FileUtils.mkdir_p test_rigfolder

      p "Copying all view files and potential javascript fixture folders so the jasmine-coverage run has access to the html fixtures."
      FileUtils.mkdir_p "#{test_rigfolder}/target/fixtures"
      FileUtils.copy_entry("#{Jasmine::Coverage.output_dir}/../fixtures", "#{test_rigfolder}/target/fixtures") rescue nil
      FileUtils.mkdir_p "#{test_rigfolder}/target/views"
      FileUtils.copy_entry("#{Jasmine::Coverage.output_dir}/../views", "#{test_rigfolder}/target/views") rescue nil

      # Here we must also copy the spec and app folders to that we have access to all the files if we need them for the test rig
      FileUtils.copy_entry("#{Jasmine::Coverage.output_dir}/../../spec", "#{test_rigfolder}/spec")
      FileUtils.copy_entry("#{Jasmine::Coverage.output_dir}/../../app", "#{test_rigfolder}/app")

      jss = str.scan(/<script type="text\/javascript" src="(.*)"><\/script>/)
      jss << str.scan(/<link rel="stylesheet" href="(.*)" type="text\/css" \/>/)
      jss << str.scan(/\.coffee\.js'\] = '(.*)';<\/script>/)
      jss.flatten!
      jss.each { |s|
        js = File.basename(s)
        str.sub!(s, js)
        if File.exists?("#{test_rigfolder}/#{js}") && js != 'index.js'
          s = "\n\n*****************************************************************************************************************\n"
          s = s + "Cannot copy file '#{js}' into jasmine coverage test rig folder.\n"
          s = s + "There is already another file of that name. You either have two files with the same name (but in different paths)\n"
          s = s + "or your filename is the same as that from a third party vendor.\n"
          s = s + "The problem stems from the fact that to run all js files from one folder (as is required by a serverless jasmine\n"
          s = s + "test), all your js files must have unique names, even if they are in different folders in your app hierarchy.\n"
          s = s + "*****************************************************************************************************************\n\n"
          raise s
        end
        FileUtils.cp(s, test_rigfolder)
      }

      outfile = "#{test_rigfolder}/jscoverage-test-rig.html"
      aFile = File.new(outfile, "w")
      aFile.write(str)
      aFile.close

      ret
    end
  end
end

# Here we patch the resource handler to output the location of our instrumented files
module Jasmine::Headless
  class FilesList

    alias old_to_html :to_html

    def to_html(files)
      # Declare our test runner files
      cov_files = ['/jscoverage.js', '/coverage_output_generator.js']

      # Add the original files, remapping to instrumented where necessary
      tags = []
      (old_to_html files).each do |path|
        files_map = Jasmine::Coverage.resources
        files_map.keys.each do |folder|
          path = path.sub(folder, files_map[folder])

          # Here we must check the supplied config hasn't pulled in our jscoverage runner file.
          # If it has, the tests will fire too early, capturing only minimal coverage
          if cov_files.select { |f| path.include?(f) }.length > 0
            fail "Assets defined by jasmine.yml must not include any of #{cov_files}: #{path}"
          end

        end
        tags << path
      end

      # Attach the "in context" test runners
      tags = tags + old_to_html(cov_files.map { |f| File.dirname(__FILE__)+f })

      tags
    end

    alias old_sprockets_environment :sprockets_environment

    def sprockets_environment
      return @sprockets_environment if @sprockets_environment
      old_sprockets_environment
      # Add the location of our jscoverage.js
      @sprockets_environment.append_path(File.dirname(__FILE__))
      @sprockets_environment
    end
  end
end