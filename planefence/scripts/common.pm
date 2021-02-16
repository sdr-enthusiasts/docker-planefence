#!/usr/bin/perl -w
# Ted Sluis 2015-12-20
# Filename : common.pm
#===============================================================================
# common sub routines
#===============================================================================
package common;
use strict;
use warnings;
use POSIX qw(strftime);
use Time::Local;
use Getopt::Long;
use File::Basename;
use Cwd;
use Term::ANSIColor qw(:constants);
#===============================================================================
my %setting;
my $myDebug;
my $interactive = 0;
my $account;
my $verbose;
my $logfile;
my @errorlog;
my @tmplog;
#===============================================================================
sub InteractiveShellCheck(@) {
        #
        # Do we run this script interactive or not?
        # If so, turn on verbose logging.
        #
        # Input: none. You can force interactive or non interactive mode using 0 or 1.
        # Return: 1=interactive, 0=not interactive.
        #
        if ( defined ($_[0]) && $_[0] eq "common" ) { shift; }
        if ( defined ($_[0]) ){
		# Force interactive or non interactive mode using 0 or 1.
                if ($_[0]){
                        $interactive = 0;
                        LOG($logfile,"Forcing Interactive to OFF","D");
                        return 0;
                } else {
                        $interactive = 1;
                        LOG($logfile,"Forcing Interactive to ON","D");
                        return 1;
                }
        }
        if ($myDebug){
                if (-t STDIN){
                        LOG($logfile,"Interactivity test -> STDIN = 1","D");
                } else {
                        LOG($logfile,"Interactivity test -> STDIN = 0","D");
                }
                if (-t STDOUT){
                        LOG($logfile,"Interactivity test -> STDOUT = 1","D");
                } else {
                        LOG($logfile,"Interactivity test -> STDOUT = 0","D");
                }
        }
        if (-t STDIN && -t STDOUT){
                # Running interactive
                $interactive = 1;
                return 1;
        }
        return 0;
}
#===============================================================================
sub Account(@){
        #
	# Determine the account that is being used.
        #
        # Input: none
        # Return: hash with key;
        #               user
        #
        if ( defined ($_[0]) && $_[0] eq "common" ) { shift; }
        $account = `id -u --name`;
        chop($account);
	LOG($logfile,"Account=$account","D");
        return $account;
}
$account = Account();
#===============================================================================
# Read configfile
sub READCONFIG(@) {
	#
	# This routine will read the config file.
	# It looks for the sections and ignor those which do not apply.
	# It checks the INI file format and removes comments.
	#
	if ( defined($_[0]) && $_[0] eq "common" ) { shift; }
	# config file name:
	my $config = shift;
	# full scriptname:
	my $fullscriptname = shift;
	my %config;
        my $scriptname  = basename($fullscriptname);
        my $directoryname = dirname($fullscriptname);
	# path to config file
	$config = $directoryname.'/'.$config;
	LOG($logfile,"Reading parameters and values from '$config' config file:","L");
	if (!-e $config) {
		LOG($logfile,"Can not read config! Config file '$config' does not exists!","W");
		return 0;
	} elsif (!-r $config) {
		LOG($logfile,"Can not read config! Config file '$config' is not readable!","W");
		return 0;
	} else {
		my @cmd = `cat $config`;
		my $section;
		foreach my $line (@cmd) {
			chomp($line);
			# skip lines with comments:
			next if ($line =~ /^\s*#\s$|^\s*#\s*[^=]*$|^\s*#\s*[^=]*$|^\s*#\s*[^=]*[=]{2,}[^=]*$/);
			# skip blank lines:
			next if ($line =~ /^\s*$/);
			# Get section:
			if ($line =~ /^\s*\[([^\]]+)\]\s*(#.*)?$/) {
				$section = $1;
				LOG($logfile,"Section: [$section]","L") if (($section =~ /common/) || ($scriptname =~ /$section|install/));
				next;
			} elsif ($line =~ /^(#?[^=]+)=([^\#]*)(#.*)?$/) {
				# Get paramter & value
				my $parameter = $1;
				my $value = $2;
				# remove any white spaces at the begin and the end:
				$parameter =~ s/^\s*|\s*$//g;
				$value     =~ s/^\s*|\s*$//g;
				# Skip invalid lines:
				if ((!$parameter) || ($parameter =~ /^\s*$/)) {
					LOG($logfile,"The line '$line' in config file '$config' is invalid! No parameter specified!","W");
					next;
				}
				if ((!$section) || ($section =~ /^\s*$/)) {
					LOG($logfile,"The line '$line' in config file '$config' is invalid! No section specified jet!","W");
					next;
				}
				if (($parameter !~ /^#/) && (exists $config{$section}) && (exists $config{$section}{$parameter})) {
					LOG($logfile,"The line '$line' in section '$section' in config file '$config' does already exists! It has value '$config{$section}{$parameter}'. This line will be skipped.","W");
					next;
				}
				# save section, parameter & value
				next unless (($section =~ /common/) || ($scriptname =~ /$section|install/));
				$config{$section}{$parameter} = $value;
				LOG($logfile,"   $parameter = $value","L");
			} else {
				# Invalid line:
				LOG($logfile,"The line '$line' in config file '$config' is invalid!","W");
				LOG($logfile,"Valid lines looks like:","I");
				LOG($logfile,"# comment line","I");
				LOG($logfile,"[some_section_name]","I");
				LOG($logfile,"parameter=value","I");
				LOG($logfile,"Comment text (started with #) behind a section or parameter=value is allowed!","I");
				next;
			}
		}
	}
	%setting = %config;
	return %config;
}
#===============================================================================
sub LOGset(@){
        #
        # LOGset routine sets the log path. If the log file does
	# not exists, it will be created and the permissions will
	# be set.
        #
        # Input: path to log file.
        # Input: log file name.
        # Return: full path and log file name.
        #
        if ( defined($_[0]) && $_[0] eq "common" ) { shift; }
        my $logpath = shift;
        my $name = shift;
	if (!-d $logpath) {
                LOG($logfile,"The log file directory '$logpath' does not exists!","E");
                exit 1;
        }
	if (!-x $logpath) {
		LOG($logfile,"The log file directory '$logpath' is not writeable!","E");
		exit 1;
	}
        $logfile =  "$logpath/$name";
        system("touch $logfile") unless (-f $logfile);
        chmod(0666,$logfile);
        LOG($logfile,"=== NEW RUN MARKER ============================","H");
	LOG($logfile,"Log file: '$logfile'","I");
        return $logfile;
}
#===============================================================================
sub setdebug(@){
        #
        # Sets debug mode and triggers verbose logging
        #
        # Input: none
        # Return: none
        #
        if ( $_[0] eq "common" ) { shift; }
        $myDebug += 1;
        LOG($logfile,"Setting debug ON!","I");
        LOGverbose();
}
#===============================================================================
sub LOGverbose(@){
        #
        # Sets verbose logging mode.
        #
        # Input: none or 'off' to disable verbose logging.
        # Return: none
        #
        if ( defined($_[0]) && $_[0] eq "common" ) { shift; }
        my $level = shift || 0;
        if ($level eq "off"){
                $verbose = 0;
                LOG($logfile,"Setting verbose OFF due to off switch.","D");
                return;
        }
        $verbose = 1;
        LOG($logfile,"Setting verbose ON.","D");
}
#===============================================================================
sub LOG(@) {
	#
	# Write messages to log file and display.
	# Adds alert color to Debug messages, Errors and Warnings.
	#
        # first field must be log file.
        # second field must be message.
        # third field informational or error.
        #
        if ( defined($_[0]) && $_[0] eq "common" ) { shift; }
        my $LOG  = shift || "";
        my $text = shift || "";
        my $type = shift || "I";
	#
	# D = Debug message.
	# E = Error message.
	# H = Log file only, reservered for === NEW RUN MARKER ===.
	# I = Informational log message.
	# L = Log file only, but can be displayed using verbose.
	# W = Warning message.
	# Lower case e, i or w are equel to E, I or W, but will be displayed on STDOUT without newline.
	#
	# Test type
        if ( $type eq "D" ){
                # Displays debug info whenever debug is on.
                return unless $myDebug;
                $text = sprintf("pid=%-5s ",$$).(sprintf MAGENTA). "$type **DEBUG** $account $text" .sprintf RESET;
        } elsif ( $type =~ /H/ ) {
		# Writes only to log file:
                $text = sprintf("pid=%-5s ",$$)."- $account $text";
        } elsif ( $type =~ /I|i/ ) {
		# Informational log message for log file & display.
                $text = sprintf("pid=%-5s ",$$).uc($type)." $account $text";
	} elsif ( $type =~ /L/ ) {
                # Informational log message for log file only.
                $text = sprintf("pid=%-5s ",$$)."$type $account $text";
        } elsif ( $type =~ /E|e/ ) {
		# Error message
                $text = sprintf("pid=%-5s ",$$).(sprintf RED).uc($type)." $account $text" .sprintf RESET;
        } elsif ( $type =~ /W|w/ ) {
		# Warning message
                $text = sprintf("pid=%-5s ",$$).(sprintf YELLOW).uc($type)." $account $text" .sprintf RESET;
        } else {
                # Every other type of message
                $text = sprintf("pid=%-5s ",$$)."I $account $text (onbekend logtype=$type)";
        }
        $text = strftime("%d%b%y %H:%M:%S", localtime())." $text";
	# Added to message queue
	if (($type =~ /H/) && ($text) && ($text =~ /NEW\sRUN\sMARKER/)) {
		# Add on start
		unshift(@tmplog,$text);
	} else {
		# Add on end
		push(@tmplog,$text);
	}
	# Do we have a log file jet?
	if (($LOG) && ($LOG !~ /^\s*$/) && (-w $LOG)) {
        	# Write all messages in queue to log file.
        	open (OUT,">>$LOG") or die "Cannot open logfile '$LOG' for output; Reason $! ! \n";
		foreach my $line (@tmplog) {
			# remove ansi codes before writing to log file.
			$line =~ s/\x1b\[[0-9;]*m//g;
        		print OUT $line."\n";
		}
		# empty message queue
		@tmplog=();
        	close OUT;
	}
	#
        return if $type eq "H";
        # Write message to display
        if (($interactive) && ((($type =~ /L/) && ($verbose)) || ($type =~ /[EeIiDWw]/))) {
        	print $text;
		print "\n" unless ($type =~ /[eiw]/);
        }
	# Store Errors & Warnings
        if ( $type =~ /[EW]{1}/ ){
		# remove ansi codes before writing to log file.
		$text =~ s/\x1b\[[0-9;]*m//g;
                push(@errorlog,"$type;$text");
        }
} # Einde LOG
#===============================================================================
sub SetOutput(@) {
	#
	# Set output file name
        #
        # first field must be the path
        # second field must be filename+extention, for example data.csv
        # third field: override file: yes or no
        # fourth field: add timestamp to file name: yes or no
        # fifth field: add sequence number to file name: yes or no
        #
        if ( defined($_[0]) && $_[0] eq "common" ) { shift; }
        my $outputdirectory  = shift || "/tmp";
        my $outputdatafile   = shift || "output.csv";
	my $override         = shift || "no";
	my $timestamp        = shift || "yes";
	my $sequencenumber   = shift || "yes";
	#
	my ($name,$extention) = $outputdatafile =~ /^([^\.]+)(\.[^\.]*)?$/;
	$name      = $name || "output";
	$extention = $extention || ".csv";
	LOG($logfile,"outputdirectory=$outputdirectory,outputdatafile=$outputdatafile(name=$name,extention=$extention),override=$override,timestamp=$timestamp,sequencenumber=$sequencenumber.","L");
	# Add timestamp
	my ($second,$day,$month,$year,$minute,$hour) = (localtime)[0,3,4,5,1,2];
	my $date = sprintf '%02d%02d%02d-%02d%02d%02d', $year-100,($month+1),$day,$hour,$minute,$second;
	$name .= '-'.$date if ($timestamp eq "yes");
	# Add sequence number.
	if ($sequencenumber eq "yes") {
	        my $mask = "'$name*$extention'";
		LOG($logfile,"search for file with mask '$mask' in '$outputdirectory'.","L");
        	my @files = `find $outputdirectory -name $mask | sort`;
	        my %files;
        	foreach my $file (@files) {
			chomp($file);
			# Get sequence number from file name:
                	if ($file =~ /\Q${name}\E-(\d+)\Q${extention}\E/) {
	                	$files{$1} = $file;
				LOG($logfile,"$1 = $files{$1}","L");
			}
        	}
		my $seqnum;
 	       	if ((keys %files) == 0) {
        	        $seqnum = 0;
	        } else {
        	        my @junk;
			# Get last sequence number:
                	($seqnum,@junk) = reverse sort keys %files;
	        }
		# Next sequence number:
		$seqnum++;
        	$name .= '-'.sprintf '%03d',$seqnum;
	}
	# Set file name:
	$outputdatafile = $outputdirectory.'/'.$name.$extention;
	if (($override eq "no") && (-e $outputdatafile)) {
		LOG($logfile,"The outputfile '$outputdatafile' already exists!","E");
		LOG($logfile,"Use the option '-override' to override the file.","E");
		LOG($logfile,"Or use the option '-timestamp' or '-sequencenumber' to add a timestamp or sequence number to the file name.","E");
		LOG($logfile,"Or better: set one of these options in the 'socket30003.cfg' config file.","E");
		exit 1;
	} elsif (($override eq "yes") && (-e $outputdatafile) && (!-w $outputdatafile)) {
		LOG($logfile,"Can not write to '$outputdatafile'! Check the permissions!","E");
		exit 1;
	}
	LOG($logfile,"Output file: '$outputdatafile'","I");
	return $outputdatafile;
}
#===============================================================================
sub GetSourceData(@){
	#
	# Get the file names of the source data
	#
	#
        if ( defined($_[0]) && $_[0] eq "common" ) { shift; }
	my $datadirectory = shift || "/tmp";
	my $filemask      = shift || "'dump*.txt'";
	#
	# Is the specified directory for the source data files readable?
	if (!-r $datadirectory) {
        	LOG($logfile, "The data directory does not exists or you have no right permissions in '$datadirectory'!","E");
        	exit 1;
	}
	# Set default filemask
	if (!$filemask) {
        	$filemask = "'dump*.txt'" ;
	} else {
        	$filemask ="'*$filemask*'";
	}
	# Find files
	my @files =`find $datadirectory -name $filemask`;
	if (@files == 0) {
        	LOG($logfile,"No files were found in '$datadirectory' that matches with the $filemask filemask!","W");
        	exit 1;
	} else {
        	LOG($logfile, "The following files fit with the filemask $filemask:","I");
	        my @tmp;
        	foreach my $file (@files) {
                	chomp($file);
			# skip log en pid files....
                	next if ($file =~ /log$|pid$/i);
                	LOG($logfile,"    $file","I");
	                push(@tmp,$file);
        	}
        	@files = @tmp;
        	if (@files == 0) {
                	LOG($logfile,"No files were found in '$datadirectory' that matches with the $filemask filemask!","W");
                	exit 1;
        	}
	}
	return @files;
}
#
#=================================================================================
#
sub CheckDirectory(@) {
	#
	# field 1 = directory type (log, output, data, pid)
	# field 2 = directory
	# field 3 = modify (yes or no)
	#
        if ( defined($_[0]) && $_[0] eq "common" ) { shift; }
        my $directorytype = shift || "directory";
        my $directory = shift;
	my $modify = shift || "yes";
	#
	my $answer;
        if ((!$directory) || ($directory =~ /^\s*$/)) {
                LOG($logfile,"There is no $directorytype directory path specified!","W");
		$directory = common->ReadInput("Specify the $directorytype directory","directory",$modify,"/tmp");
	}
	# covert relative directory path to absolute path:
	$directory = getcwd().'/'.$directory if ($directory !~ /^\//);
	$directory =~ s/\/$//;
	if ($modify eq 'yes') {
		$answer = common->ReadInput("Do you want to use '$directory' as $directorytype directory?","multiplechoice",$modify,"y","n");
		if ($answer =~ /n/i) {
			$directory = common->ReadInput("Specify the $directorytype directory","directory",$modify,$directory);
		}
	}
        if (!-e $directory) {
                LOG($logfile,"The $directorytype directory '$directory' does not exists!","I");
		my @path = split(/\//,$directory);
		my $path = "";
		foreach my $dir (@path) {
			next if ($dir =~ /^\s*$/);
			$path .= '/'.$dir;
			if (-e $path) {
				next;
			} else {
                		mkdir($path);
				chmod(0775,$path) if ((!-r $path) || (!-w $path));
				if (!-e $path) {
					LOG($logfile,"Unable to create $directorytype directory '$path'!","E");
					exit 1;
				} else {
					LOG($logfile,"The $directorytype directory '$path' has been created.","L");
				}
			}
		}
        } else {
		LOG($logfile,"The $directorytype directory '$directory' does exists.","L");
	}
        if ((!-r $directory) || (!-w $directory)) {
                LOG($logfile,"The $directorytype directory '$directory' is not readable and/or writable!","I");
		chmod($directory,0775);
		if ((!-r $directory) || (!-w $directory)) {
                	LOG($logfile,"Unable to change the permissions for the $directorytype directory '$directory'!","E");
                	exit 1;
		} else {
			LOG($logfile,"The permissions for the $directorytype directory '$directory' have been set.","I");
		}
        } else {
		LOG($logfile,"The $directorytype directory '$directory' is readable and writeable.","L");
	}
	LOG($logfile,"Selected $directorytype directory: '$directory'.","I");
	$directory =~ s/\/$//;
	return $directory;
}
#
#=================================================================================
#
sub ReadInput(@) {
	#
	# field 1 = Question.
	# fiels 2 = type: multiplechoice, directory, file, filemask, numeric, ipaddress
	# field 3 = modify (yes or no)
	# field 4... = possible ansers
	#
        if ( defined($_[0]) && $_[0] eq "common" ) { shift; }
	my $question = shift;
	my $type = shift;
	my $modify = shift;
	my @answers = $_[0];
	foreach my $a (@_) {
		push(@answers,$a) unless ($a eq $_[0]);
	}
	#
	my $answer;
	if ($type =~ /multiplechoice/) {
		my $answers = '^'.join('$|^',@answers).'$';
		if ($modify =~ /y/) {
			LOG($logfile,"$question (".join('/',@answers)."): [$answers[0]]","i");
			$answer  = <STDIN>;
		}
		chomp($answer) if ($answer);
		$answer ||= $answers[0];
		while ($answer !~ /$answers/i) {
			LOG($logfile,"The specified answer '$answer' is invalid! Try again (".join('/',@answers)."): [$answers[0]]","w");
			$answer = <STDIN>;
			chomp($answer) if ($answer);
			$answer ||= $answers[0];
		}
	} elsif ($type =~ /directory/) {
		if ($modify =~ /y/) {
			LOG($logfile,"$question: [$answers[0]]","i");
                	$answer  = <STDIN>;
		}
		chomp($answer) if ($answer);
		$answer ||= $answers[0];
                while ($answer !~ /^\/?([a-z0-9\._\-]+\/?)+/i) {
                        LOG($logfile,"The specified directory '$answer' is invalid! Try again: [$answers[0]","w");
                        $answer = <STDIN>;
			chomp($answer) if ($answer);
			$answer ||= $answers[0];
                }
	} elsif ($type =~ /^file$/) {
		if ($modify =~ /y/){
                	LOG($logfile,"$question: [$answers[0]]","i");
                	$answer  = <STDIN>;
		}
                chomp($answer) if ($answer);
                $answer ||= $answers[0];
                while ($answer !~ /^[a-z0-9\.\-_]+$/i) {
                        LOG($logfile,"The specified file '$answer' is invalid! Try again (without path): [$answers[0]","w");
                        $answer = <STDIN>;
                        chomp($answer) if ($answer);
                        $answer ||= $answers[0];
                }
        } elsif ($type =~ /^filemask$/) {
 		if ($modify =~ /y/){
                	LOG($logfile,"$question: [$answers[0]]","i");
                	$answer  = <STDIN>;
		}
                chomp($answer) if ($answer);
                $answer ||= $answers[0];
                while ($answer !~ /^[\w\d\.\-_\*\?]+$/i) {
                        LOG($logfile,"The specified filemask '$answer' is invalid! Try again: [$answers[0]","w");
                        $answer = <STDIN>;
                        chomp($answer) if ($answer);
                        $answer ||= $answers[0];
                }
         } elsif ($type =~ /^numeric$/) {
 		if ($modify =~ /y/){
                	LOG($logfile,"$question: [$answers[0]]","i");
                	$answer  = <STDIN>;
		}
                chomp($answer) if ($answer);
                $answer ||= $answers[0];
                while ($answer !~ /^[\+\-]?\d+(\.\d+)?$/i) {
                        LOG($logfile,"The specified numeric value '$answer' is invalid! Try again: [$answers[0]","w");
                        $answer = <STDIN>;
                        chomp($answer) if ($answer);
                        $answer ||= $answers[0];
                }
        } elsif ($type =~ /^ipaddress$/) {
 		if ($modify =~ /y/){
                	LOG($logfile,"$question: [$answers[0]]","i");
                	$answer  = <STDIN>;
		}
                chomp($answer) if ($answer);
                $answer ||= $answers[0];
                while ($answer !~ /^\d+\.\d+\.\d+\.\d+$/i) {
                        LOG($logfile,"The specified filemask '$answer' is invalid! Try again: [$answers[0]","w");
                        $answer = <STDIN>;
                        chomp($answer) if ($answer);
                        $answer ||= $answers[0];
                }
        }
	return $answer;
}
1;
