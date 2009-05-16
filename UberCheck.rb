
=begin

Ubernet Bulk Check of Enforced Downloaded Files.

This program will examine the files in the Ubernet download directory (and optionally in
the "needs attention" directory and check for severalpossible non-standard issues. 
If the directory passes (i.e. no issues detected) the directory will be moved to a 
"good" location, else the directory is moved to a location to be corrected.

When run from the "needs attention" directory the file is moved to the "good" directory
or left in place for further processing. This allows for multiple passes when adjusting
tags and other elements of the CD.

A database table is built for both good and "needs attention" details.

options: 
  
  -C (check)    : runs the program, builds the database tables, does not move the files.
  -X (execute)  : runs the program, builds the database tables, moves the files.
  -A (attention) : runs the check or execute from the 'needs attention' directory.
                 
The output will be in two tables called 'ucgood' and 'ucattention' in the 'ubercheck' database. Use
the following SQL to sort:

  SELECT * FROM 'ubercheck', 'ufcompares' ORDER BY 'artist', 'title'
  
checks:

    a. Is directory empty of MP3 files?
    b. Does the directory have a 'folder.jpg' file?
    c. Are the file names in leading capitalization format?
    d. Does the MP3 have a 'year' tag?
  
v.1.0.0
04/19/2009

04/22/2009: version 1.0 - Initial program version.


=end  

require 'find'
require 'ftools'

# =====================================================================
#
# Establish the connection to the database.
#
# This program uses MySql and assumes the setup is taken care of. The 
# code below is re-using the Junqbox AppPlatform connection data.
#
# A database named "ubercheck" must be created prior to running this application.
#
# =====================================================================
require 'active_record'

# ActiveRecord::Base.logger = Logger.new(STDERR)

ActiveRecord::Base.establish_connection(
    :adapter => "mysql", 
    :database => "ubercheck",
    :username => "root",
    :password => "junqboxdev",
    :host => "localhost")
  
# Define the data model  
class Ucgood < ActiveRecord::Base
end

class Ucattention < ActiveRecord::Base
end
    
# =====================================================================

# Usage check class
class UsageCheck

    def initialize
            
        *@ARGV = *ARGV.map{|a|a.upcase}
    end
    
    def length
        @ARGV.length
    end
    
    def message
        puts "\nUberCheck - Ubernet Bulk Check of Enforced Downloaded Files."
        puts "\n\noptions: -C : runs the program, builds the database tables, does not move the files."
        puts "         -X : runs the program, builds the database tables, moves the files."
        puts "         -A (optional) : runs the check or execute from the 'needs attention' directory.\n"

    end
    
    def option_1
        @ARGV[0]
    end  

    def option_2
        @ARGV[1]
    end
    
end

# Check class
class Check
    
    def initialize(mode_flag, directory)
        
        ActiveRecord::Schema.verbose = false
        
        ActiveRecord::Schema.define do
            create_table :ucgoods, :force => true do |table|
                table.column :artist, :string
                table.column :year, :string
                table.column :title, :string
            end
            
            add_index :ucgoods, [:artist]
            add_index :ucgoods, [:year]
            add_index :ucgoods, [:title]
        end  
        
        ActiveRecord::Schema.define do
            create_table :ucattentions, :force => true do |table|
                table.column :error, :string
                table.column :artist, :string
                table.column :year, :string
                table.column :title, :string
            end
            
            add_index :ucattentions, [:error]
            add_index :ucattentions, [:artist]
            add_index :ucattentions, [:year]
            add_index :ucattentions, [:title]
        end
        
        # Set program constants and globals
        
        $program_mode = mode_flag
        $dl_dir = "D:/- Downloading -/Uber/MP3"
        $good_dir = "D:/- Downloading -/Uber/MP3 - Good"
        $attn_dir = "D:/- Downloading -/Uber/MP3 - Attention"
        
        # Assume that the download directory exists (dirs have to be enforced
        # before being checked...
        
        # Create the "good" and "needs attention" directories
        File.makedirs $good_dir
        File.makedirs $attn_dir
        
        if directory == "attn_dir"
            $check_dir = $attn_dir
        else
            $check_dir = $dl_dir
        end
   
    end

    def create
        
        # Define globals
        
        $good_album_count = 0
        $bad_album_count = 0
        
        # Look at each directory in the download directory.
        
        Find::find($check_dir) {|next_directory|

            if next_directory != $check_dir   # Skip the home directory
            
                if (File::directory?(next_directory))
                    # Next directory found                    
                    process_directory(next_directory)
                else
                    # This is not a directory, so ignore
                    Find.prune()
                end
                
            end
     
        }
        
    end
        
    def process_directory(next_directory)
        
        # Only process directories with the pattern "artist - title" or "artist - year - title" 
        # All else need to be looked at

        # First parse the directory tree out
        
        dir_array = Array.new
        dir_array = next_directory.split("/")
        
        # The last array element holds the directory name
        # Break it into artist, year, & title
        
        name_array = Array.new
        name_array = dir_array[dir_array.size-1].split(" - ")
        
        if ((name_array.size == 2) || (name_array.size == 3))
            
            if ((name_array.size == 2) && (name_array[1].length == 4))
                # It's possible that this is a VA album
                if name_array[1].to_i != 0 # This conversion will fail if not a number
                    # Set up the standard format with "Various Artists" as the artist tag
                    # Format: "Various Artists" "Year" "Title"
                    name_array[2] = name_array[0]
                    name_array[0] = "Various Artists"
                else
                    # Directory does not have a 'year' tag **NEEDS ATTENTION**
                    data_record = Ucattention.new
                        data_record.error = "No YEAR tag"
                        data_record.artist = name_array[0]
                        data_record.year = "no"
                        data_record.title = name_array[1]
                    data_record.save
                    puts format("\n\n Artist: %s Year: %s Title: %s", name_array[0], "No YEAR tag", name_array[1])
                    $bad_album_count = $bad_album_count + 1
                    
                    if $program_mode == "move_files"
                        File.move(next_directory, $attn_dir)
                    end
                    
                    return
                end
            else
                if ((name_array.size == 2) && (name_array[1].length != 4))
                    # Directory does not have a 'year' tag **NEEDS ATTENTION**
                    data_record = Ucattention.new
                        data_record.error = "No YEAR tag"
                        data_record.artist = name_array[0]
                        data_record.year = "no"
                        data_record.title = name_array[1]
                    data_record.save
                    puts format("\n\n Artist: %s Year: %s Title: %s", name_array[0], "No YEAR tag", name_array[1])
                    $bad_album_count = $bad_album_count + 1
                    
                    if $program_mode == "move_files"
                        File.move(next_directory, $attn_dir)
                    end
                    
                    return
                end
            end
            
            # All name_array records should be 3 elements at this point
            
            # At this point we need to step into the directory to examine in more detail
           
            process_CD(next_directory, name_array)
            
        else
            # **NEEDS ATTENTION** General error
            data_record = Ucattention.new
                data_record.error = "General Error"
                data_record.artist = name_array[0]
                data_record.year = name_array[1]
                data_record.title = name_array[2]
            data_record.save
            puts format("\n\n General Error!! Artist: %s Year: %s Title: %s", name_array[0], name_array[1], name_array[2])
            $bad_album_count = $bad_album_count + 1
            
            if $program_mode == "move_files"
                File.move(next_directory, $attn_dir)
            end
            
            return
        end

        
    end
    
    def process_CD(next_directory, name_array)
        
        # next_directory is the fully qualified directory (from the root drive)
        # name_array is: [0] Artist, [1] Year, [2] Title
        
        # Look at each file in the current directory. Keep running track of issues.
        
        # At this point we are looking for:
        #
        #       a. Is directory empty of MP3 files?
        #       b. Does the directory have a 'folder.jpg' file?
        #       c. Are the file names in leading capitalization format? 

        mp3_files = false       # Assume no MP3 files
        folder_JPG = false      # Assume no cover art file
        leading_cap = true      # Assume that the leading cap structure is followed
        
        # Check to see if the CD follows the leading cap structure
                    
        cd = name_array[2]
                    
        if ((ret_code = case_check(cd)) != 0)
            leading_cap = false
        end
        
        
        Find::find(next_directory) {|next_file|
            
            if next_file != next_directory    # Skip the home directory
           
                if (File::directory?(next_file))
                    # This is a directory, so ignore 
                    Find.prune()
                else
                    # This is a file, so process
               
                    # Check to see if this is an MP3 file
                    
                    file_array = Array.new
                    file_array = next_file.split(".")
                                        
                    if file_array.last.upcase == "MP3"
                        mp3_files = true                # At least 1 MP3 file contained
                    end
                    
                    # Check to see if this is the cover art file
                    # This check fails if the "folder.jpg" file is not all lowercase
                    
                    if next_file.include? "folder.jpg"
                        folder_JPG = true
                    end
                    
                    # Check to see if the MP3 follows the leading cap structure

                    mp3 = next_file.split("/").last.split("-").last.strip  
                    
                    mp3_array = Array.new
                    mp3_array = mp3.split(".")

                    if mp3_array.last.upcase == "MP3"

                        if ((ret_code = case_check(mp3_array[0])) != 0)
                            leading_cap = false
                        else
                            # MP3 is good, continue
                        end
                    end
                end
            end
        }
        
        # Results

        
        # Check for success
        if ((mp3_files == true) && (folder_JPG == true) && (leading_cap == true))
            # Success, create a "good" data record and (optionally) move the file
            data_record = Ucgood.new
            
            if $program_mode == "move_files"
                File.move(next_directory, $good_dir)
            end
            
                    
            $good_album_count = $good_album_count + 1
            
        else
            # Failure, create an attention data record and (optionally) move the file
            data_record = Ucattention.new
            
            if $program_mode == "move_files"
                File.move(next_directory, $attn_dir)
            end
            
            $bad_album_count = $bad_album_count + 1
            
        end
            
        data_record.artist = name_array[0]
        data_record.year = name_array[1]
        data_record.title = name_array[2]
        
        puts format("\n\n Artist: %s Year: %s Title: %s", name_array[0], name_array[1], name_array[2])
        
        if mp3_files == true
            printf(" MP3's: YES")
        else
            printf(" MP3's: NO")
            data_record.error = "No MP3 Files"
        end
        
        if folder_JPG == true
            printf(" Cover Art: YES")
        else
            printf(" Cover Art: NO")
            data_record.error = "No Cover Art"
        end 
        
        if leading_cap == true
            printf(" Capitalization: YES")
        else
            printf(" Capitalization: NO")
            data_record.error = "Not Capitalized"
        end 
                
        data_record.save
        
    end
    
    def case_check(title)    
        
        title.each(' ') {|title_words|
        
            # Check for parens
            if title_words[0,1] == '('
                title_words.delete! "("                
            end
            
            # Check for brackets
            if title_words[0,1] == '['
                title_words.delete! "["                
            end
        
            if ((title_words[0,1] >= 'A') && (title_words[0,1] <= 'Z'))
                # first character is uppercase
                # check the next character for lowercase, assume is true then the rest of the word is lowercase
                # first check to see if there is a second character
                if title_words.length != 2
                    if ((title_words[1,1] >= 'a') && (title_words[1,1] <= 'z'))
                        # second character is lowercasecase
                        # continue looping
                    else
                        # second character is not lowercase                 
                        return(-2) # Bad return code
                    end
                end
            else
                # first character is not uppercase            
                return(-1) # Bad return code
            end
            
        }
        
        return(0) # 0 is a good return code
    
    end
    
    def report
        
        printf("\n\n ========================================")
        puts format("\n\n Good CD's: %d - Needs Attention CD's: %d", $good_album_count, $bad_album_count)
        printf("\n ========================================")
        puts "\n\n Processing complete."
        
    end

end
  
# =====================================================================================
# Program execution starts here
# =====================================================================================

u = UsageCheck.new

if u.length == 0
    u.message
else
    
    if u.option_2 == '-A'
        check_dir = "attn_dir"
    else
        check_dir = "dl_dir"
    end
    
    # Check the passed in command option
    case u.option_1
      
        when "-C"
            puts "\n Starting to check (only) downloaded Ubernet music files...\n"
            new_comparison = Check.new("check_only", check_dir)
            new_comparison.create
            new_comparison.report
        when "-X"
            puts "\n Starting to check and move downloaded Ubernet music files...\n"
            new_comparison = Check.new("move_files", check_dir)
            new_comparison.create
            new_comparison.report
        else
            puts "\nCheck the available options!"
            u.message
    end
end