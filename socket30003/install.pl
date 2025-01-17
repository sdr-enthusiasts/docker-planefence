#!/usr/bin/perl -w
# ted.sluis@gmail.com
# Filename : install.pl
#
#===============================================================================
BEGIN {
	use strict;
	use POSIX qw(strftime);
	use Time::Local;
	use Getopt::Long;
	use File::Basename;
	use File::Copy;
	use Math::Complex;
        use Cwd 'abs_path';
        our $scriptname  = basename($0);
        our $fullscriptname = abs_path($0);
        use lib dirname (__FILE__);
        use common;
}
#
#===============================================================================
# Ctrl-C interupt handler
$SIG{'INT'} = \&intHandler;

sub intHandler {
	# Someone pressed Ctrl-C
	my $answer = common->ReadInput("CTRL-C was pressed. Do you want to exit '$scriptname'?","regular","y","n");
	if ((!$answer) || ($answer =~ /^y$/i)) {
		LOG("Exiting '$scriptname'.....","I");
		exit 1;
	} else {
		LOG("'$scriptname' is continuing.......","I");
	}
}
#===============================================================================
# Get options
my $help;
my $datadirectory;
my $installdirectory;
my $logdirectory;
my $outputdirectory;
my $piddirectory;
my $modify = "no";
GetOptions(
	"help!"=>\$help,
	"install=s"=>\$installdirectory,
	"data=s"=>\$datadirectory,
	"log=s"=>\$logdirectory,
	"pid=s"=>\$piddirectory,
	"output=s"=>\$outputdirectory,
	"modify!"=>\$modify,
        "debug!"=>\$debug,
        "verbose!"=>\$verbose
) or exit(1);
$modify = "yes" if ($modify !~ /no/);
print "modify=$modify\n";
#
#===============================================================================
# if '-debug' parameter is used, set debug mode:
common->setdebug if ($debug);
#
#===============================================================================
# if '-verbose' parameter is used, set verbose mode:
common->LOGverbose if ($verbose);
#
#===============================================================================
# Checks if script runs interactive.
my $interactive = common->InteractiveShellCheck;
#
#===============================================================================
# Log routine
sub LOG(@){
        common->LOG($logfile,@_);
}
#
#=============================================================================== 
# Check options:
if ($help) {
	print "\nThis $scriptname script installs the socket30003 scripts.
It will create the directories, copy the files, check and set the permissions.
In case of an update, it will backup the original config file and add new 
parameters if applicable.

Please read this post for more info:
http://discussions.flightaware.com/post180185.html#p180185

Syntax: $scriptname

Optional parameters:
  -install <install       The script will be installed in
            directory>    '/home/pi/socket30003' by default.
  -data <data directory>  The data files will be stored in 
                          '/tmp' by default.
  -log  <data directory>  The log files will be stored in 
                          '/tmp' by default.
  -output <output         The output files will be stored in 
            directory>    '' by default.
  -pid <pid directory>    The pid files will be stored in
                          '/tmp'.
  -debug                  Displays raw socket messages.
  -verbose                Displays verbose log messages.
  -help                   This help page.

Examples:
  $scriptname 
  $scriptname -install /user/share/socket30003
  $scriptname -data /home/pi/data -log /home/pi/log -output /home/pi/result \n\n";
	exit 0;
}

#
#===============================================================================
# Read settings from config file
my %setting = common->READCONFIG('socket30003.cfg',$fullscriptname);
# Use parameters & values from the 'install' section. If empty or not-exists, then use from the 'common' section, otherwise script defaults.
$installdirectory = $installdirectory  || $setting{'install'}{'installdirectory'} || "/home/pi/socket30003";
$datadirectory    = $datadirectory     || $setting{'install'}{'datadirectory'}    || $setting{'common'}{'datadirectory'}    || "/tmp";
$logdirectory     = $logdirectory      || $setting{'install'}{'logdirectory'}     || $setting{'common'}{'logdirectory'}     || "/tmp";
$piddirectory     = $piddirectory      || $setting{'install'}{'piddirectory'}     || $setting{'common'}{'piddirectory'}     || "/tmp";
$outputdirectory  = $outputdirectory   || $setting{'install'}{'outputdirectory'}  || $setting{'common'}{'outputdirectory'}  || "/tmp";
#
#=============================================================================== 
# Does the directory exist? Is it readable and writable?
$installdirectory = common->CheckDirectory('install',$installdirectory);
#=============================================================================== 
# Look for old config file
my %oldsetting;
my $oldconfigfile = $installdirectory.'/socket30003.cfg';
if (-e $oldconfigfile) {
	LOG("Config file found in install directory! Reading config file....","I");
	%oldsetting = common->READCONFIG('socket30003.cfg',$installdirectory.'/install.pl');
}
#===============================================================================
#
my $currentdirectory = dirname($fullscriptname);
my $configfile = $currentdirectory.'/socket30003.cfg';
if (!-e $configfile) {
	LOG("The is no '$configfile' config file found in the source directory!","E");
	exit 1;
}
my @cmd = `cat $configfile`;
my $section;
my @config;
my %comment;
my %checkconfigfile;
foreach my $line (@cmd) {
	chomp($line);
        # save lines with comments:
        if ($line =~ /^\s*#\s$|^\s*#\s*[^=]*$|^\s*#\s*[^=]*$|^\s*#\s*[^=]*[=]{2,}[^=]*$/) {
		push(@config,$line);
		next;
	}
        # save blank lines:
        if ((!$line) || ($line =~ /^\s*$/)) {
		push(@config,"");
		next;
	}
        # Get section:
        if ($line =~ /^\s*\[([^\]]+)\]\s*(#.*)?$/) {
        	$section = $1;
		push(@config,$line);
        	LOG("Section: [$section]","I");
        	next;
        } elsif ($line =~ /^(#?[^=]+)=([^\#]*)(#.*)?$/) {
        	# Get paramter & value
                my $parameter = $1;
                my $value     = $2 || "";
		my $comment   = $3 || "";
                # remove any white spaces at the begin and the end:
                $parameter =~ s/^\s*|\s*$//g;
                $value     =~ s/^\s*|(\s*)$//g;
		# Add spaces to comment:
		$comment = ($1 || "").$comment;
		# Skip invalid lines:
                if ((!$parameter) || ($parameter =~ /^\s*$/)) {
                	LOG("The line '$line' in config file '$configfile' is invalid! No parameter specified!","W");
                        next;
                }
                if ((!$section) || ($section =~ /^\s*$/)) {
                	LOG("The line '$line' in config file '$configfile' is invalid! No section specified jet!","W");
                        next;
                }
		if ((exists $checkconfigfile{$section}) && ($checkconfigfile{$section}{$parameter})) {
			LOG("The line '$line' in config file '$configfile' already exists! It has value '$checkconfigfile{$section}{$parameter}'.","W");
		}
		# Use value from existing config file if it is different: 
		my $par = $parameter;
		my $param = $parameter;
		$par =~ s/^#//;
		# compare value existing config with source config.
		if ((exists $oldsetting{$section}) && ($oldsetting{$section}{$par}) && ($oldsetting{$section}{$par} !~ /^\Q$value\E$/)) {
			$val = $oldsetting{$section}{$par};
		} else {
			$val = $value;
		}
		# compare parameter existing config with source config.
		if ((exists $oldsetting{$section}) && (exists $oldsetting{$section}{'#'.$par})) {
			$parameter = '#'.$par;
		} elsif ((exists $oldsetting{$section}) && (exists $oldsetting{$section}{$par})) {
			$parameter = $par;
		}
		$par = $param;
		#
		my $answer;
		if ($modify =~ /yes/) {
			if ($parameter =~ /^#/) {
				$answer = common->ReadInput("Do you want to enable this line: '$parameter=$value'?","multiplechoice",$modify,"n","y");
				$parameter =~ s/^#// if ($answer =~ /y/);
			} else {
				$answer = common->ReadInput("Do you want to disable this line: '$parameter=$value'?","multiplechoice",$modify,"n","y");
				$parameter = '#'.$parameter if ($answer =~ /y/);
			}
		}
		# 
		if ($parameter !~ /^#/) {
                	# save section, parameter & value
                	$checkconfigfile{$section}{$parameter} = $value;
			# Ask what values should be used: 
			if ($parameter =~ /filemask/) {
				$val = common->ReadInput("Which 'filemask' do you want to use?","filemask",$modify,"$val");
			} elsif ($parameter =~ /^#?(\w+)directory$/) {
print "VAL=$val\n";
				$val = common->CheckDirectory($1,$val,$modify);
			} elsif ($parameter =~ /distanceunit/) {
				$val = common->ReadInput("Which 'distanceunit' do you want to use?","multiplechoice",$modify,"$val","kilometer","nauticalmile","mile","meter");
			} elsif ($parameter =~ /altitudeunit/) {
				$val = common->ReadInput("Which 'altitudeunit' do you want to use?","multiplechoice",$modify,"$val","feet","meter");
			} elsif ($parameter =~ /speedunit/) {
        	                $val = common->ReadInput("Which 'speedunit' do you want to use?","multiplechoice",$modify,"$val","kilometerph","knotph","mileph");
                	} elsif ($parameter =~ /(latitude|longitude|TIME_MESSAGE_MARGIN|degrees|resolution|max_positions|max_weight|maxaltitudemeter|maxaltitudefeet|minaltitude|numberofdirections|numberofaltitudezones)/) {
				$val = common->ReadInput("Which '$1' do you want to use?","numeric",$modify,"$val");
			} elsif ($parameter =~ /(override|timestamp|sequencenumber|showpositions)/) {
				$val = common->ReadInput("Which value for '$1' do you want to use?","multiplechoice",$modify,$val,"yes","no");
			} elsif ($parameter =~ /outputdatafile/) {
				$val = common->ReadInput("Which 'outputdatafile' name do you want to use?","file",$modify,"$val");	
			} elsif ($parameter =~ /PEER_HOST/) {
                                $val = common->ReadInput("Which 'PEER_HOST' name do you want to use?","ipaddress",$modify,"$val");
                        }
		}
		# Value different as source config value?
                if ((($parameter !~ /^#/) && ($value !~ /\Q$val\E/)) || (($parameter !~ /\Q$par\E/))) { 
			if ((!exists $comment{$section}{"$line"}) || (!exists $comment{$section}{"#$line"})) {
				$line = "#".$line if ($line !~ /^#/);
				$comment{$section}{"$line"} = "";
				# Save config value as comment:
				push(@config,$line);
				LOG($line,"L");
			}
			my $changepar = "(parameter:$par)";
			$changepar = "(parameter:$par > $parameter)" if ($parameter !~ /\Q$par\E/);
			my $changeval = "(value:$value)";
			$changeval= "(value:$value > $val)" if ($value !~ /\Q$val\E/);
			LOG("from existing config: $changepar, $changeval","I");
			push(@config,"${parameter}=${val}${comment}");
                	LOG("${parameter}=${val}${comment}","L");
		} else {
			push(@config,$line);
			LOG($line,"L");
		}
	} else {
        	# Invalid line:
                LOG("The line '$line' in config file '$configfile' is invalid!","W");
                LOG("Valid lines looks like:","I");
                LOG("# comment line","I");
                LOG("[some_section_name]","I");
                LOG("parameter=value","I");
                LOG("Comment text (started with #) behind a section or parameter=value is allowed!","I");
                next;
        }
}
if ($modify =~ /no/) {
	$logdirectory    = common->CheckDirectory('log',$logdirectory,"no");
	$piddirectory    = common->CheckDirectory('pid',$piddirectory,"no");
	$datadirectory   = common->CheckDirectory('data',$datadirectory,"no");
	$outputdirectory = common->CheckDirectory('output',$outputdirectory,"no");
}
#=============================================================================== 
# Set log file path and name
my ($second,$day,$month,$year,$minute,$hour) = (localtime)[0,3,4,5,1,2];
my $filedate = 'install-'.sprintf '%02d%02d%02d', $year-100,($month+1),$day;
$logfile = common->LOGset($logdirectory,"$filedate.log",$verbose);
#
#===============================================================================
#
LOG("Current directory: $currentdirectory","I");
if ($installdirectory =~ /^\Q$currentdirectory\E\/?$/i) {
	LOG("De source directory '$currentdirectory' is the same as the install direcory, so no script files will be copied.","I");
} else {
	my @cmd = `find . -name '*' | grep -P "socket30003.cfg|rangeview.pl|common.pm|heatmap.pl|install.pl|socket30003.pl"`;
	foreach my $filepath (@cmd) {
		chomp($filepath);
		my $file = basename($filepath);
		print "file=$file, $filepath, $installdirectory/$file\n";
		copy($filepath,"$installdirectory/$file") or die "Copy failed: $!";
	}
}
my $cfg="$installdirectory/socket30003.cfg";
@cmd=`sed -i "s|^outputdirectory=.*|outputdirectory=$outputdirectory|g" $cfg`;
@cmd=`sed -i "s|^datadirectory=.*|datadirectory=$datadirectory|g"       $cfg`;
@cmd=`sed -i "s|^logdirectory=.*|logdirectory=$logdirectory|g"          $cfg`;
@cmd=`sed -i "s|^piddirectory=.*|piddirectory=$piddirectory|g"          $cfg`;
print "Finished!\n";
