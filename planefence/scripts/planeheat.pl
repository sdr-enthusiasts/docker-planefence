#!/usr/bin/perl -w
#
# ted.sluis@gmail.com
# heatmap.pl
#
#===============================================================================
# May 4, 2020: minor updates by Ramon F. Kolb
# - changed the output format from "pure" CSV to OSM/Leaflet styled arrays
# - to avoid cluttering of the heatmap, discard the bottom 3% of samples
# - All changes are documented and marked with "RFK Edit" in the comments
# Lots of thanks to Ted Sluis for this awesome utility!
#===============================================================================
BEGIN {
	use strict;
	use POSIX qw(strftime);
	use Time::Local;
	use Getopt::Long;
	use File::Basename;
	use Cwd 'abs_path';
	our $scriptname  = basename($0);
        our $fullscriptname = abs_path($0);
        use lib dirname (__FILE__);
        use common;
}
#
#===============================================================================
my $logfile ="";
#===============================================================================
# Ctrl-C interupt handler
$SIG{'INT'} = \&intHandler;

sub intHandler {
	# Someone pressed Ctrl-C
	LOG("CTRL-C was pressed. Do you want to exit '$scriptname'? (y/n)","W");
	my $answer = <STDIN>;
	if ($answer =~ /^y$/i) {
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
my $logdirectory;
my $outputdirectory;
my $outputdatafile;
my $override;
my $timestamp;
my $sequencenumber,
my $filemask;
my $longitude;
my $latitude;
my $max_positions;
my $resolution;
my $degrees;
my $max_weight;
my $debug = 0;
my $verbose = 0;

GetOptions(
	"help!"=>\$help,
	"filemask=s"=>\$filemask,
	"data=s"=>\$datadirectory,
	"log=s"=>\$logdirectory,
	"output=s"=>\$outputdirectory,
	"file=s"=>\$outputdatafile,
	"override!"=>\$override,
	"timestamp!"=>\$timestamp,
        "sequencenumber!"=>\$sequencenumber,
        "longitude=s"=>\$longitude,
        "latitude=s"=>\$latitude,
	"maxpositions=s"=>\$max_positions,
	"resolution=s"=>\$resolution,
	"degrees=s"=>\$degrees,
	"maxweight=s"=>\$max_weight,
        "debug!"=>\$debug,
        "verbose!"=>\$verbose
) or exit(1);
#
$override        = "yes" if ($override);
$timestamp       = "yes" if ($timestamp);
$sequencenumber  = "yes" if ($sequencenumber);
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
# Read settings from config file
# my %setting = common->READCONFIG('socket30003.cfg',$fullscriptname);
# Use parameters & values from the 'heatmap' section. If empty or not-exists, then use from the 'common' section, otherwise script defaults.
$datadirectory  = $datadirectory   || $setting{'heatmap'}{'datadirectory'}   || $setting{'common'}{'datadirectory'}   || "/tmp";
$logdirectory   = $logdirectory    || $setting{'heatmap'}{'logdirectory'}    || $setting{'common'}{'logdirectory'}    || "/tmp";
$outputdirectory= $outputdirectory || $setting{'heatmap'}{'outputdirectory'} || $setting{'common'}{'outputdirectory'} || "/tmp";
$latitude       = $latitude        || $setting{'heatmap'}{'latitude'}        || $setting{'common'}{'latitude'}        || 52.085624; # Antenna location
$longitude      = $longitude       || $setting{'heatmap'}{'longitude'}       || $setting{'common'}{'longitude'}       || 5.0890591; #
$filemask       = $filemask        || $setting{'heatmap'}{'filemask'}        || $setting{'common'}{'filemask'}        || "dump*txt";
$override       = $override        || $setting{'heatmap'}{'override'}        || $setting{'common'}{'override'}        || "no";  # override output file if exists.
$timestamp      = $timestamp       || $setting{'heatmap'}{'timestamp'}       || $setting{'common'}{'timestamp'}       || "no"; # add timestamp to output file name.
$sequencenumber = $sequencenumber  || $setting{'heatmap'}{'sequencenumber'}  || $setting{'common'}{'sequencenumber'}  || "no"; # add sequence number to output file name.
$outputdatafile = $outputdatafile  || $setting{'heatmap'}{'outputdatafile'}  || "heatmapdata.csv";
$degrees        = $degrees         || $setting{'heatmap'}{'degrees'}         || 5;        # used to determine boundary of area around antenne.
$resolution     = $resolution      || $setting{'heatmap'}{'resolution'}      || 1000;     # number of horizontal and vertical positions in output file.
$max_positions  = $max_positions   || $setting{'heatmap'}{'max_positions'}   || 100000;   # maximum number of positions in the outputfile.
$max_weight     = $max_weight      || $setting{'heatmap'}{'max_weight'}      || 1000;     # maximum position weight on the heatmap.
#
#===============================================================================
# Check options:
if ($help) {
	print "\nThis $scriptname script creates heatmap data
which can be displated in a modified variant of dump1090-mutobility.

It creates an output file with location data in csv format, which can
be imported using the dump1090 GUI.

Please read this post for more info:
http://discussions.flightaware.com/post180185.html#p180185

This script uses the data file(s) created by the 'socket30003.pl'
script, which are by default stored in '$outputdirectory' in this format:
dump1090-<hostname/ip_address>-YYMMDD.txt

The script will automaticly use the correct units (feet, meter,
kilometer, mile, natical mile) for 'altitude' and 'distance' when
the input files contain column headers with the unit type between
parentheses. When the input files doesn't contain column headers
(as produced by older versions of 'socket30003.pl' script)
you can specify the units using startup parameters or in the config
file. Otherwise this script will use the default units.

This script will create a heatmap of a square area around your
antenna. You can change the default range by specifing the number
of degrees -/+ to your antenna locations. (The default values will
probably satisfy.) This area will be devided in to small squares.
The default heatmap has a resolution of 1000 x 1000 squares.
The script will read all the flight position data from the source
file(s) and count the times they match with a square on the heatmap.

The more positions match with a particular square on the heatmap,
the more the 'weight' that heatmap position gets. We use only the
squares with the most matches (most 'weight) to create the heatmap.
This is because the map in the browser gets to slow when you use
too much positions in the heatmap. Of cource this also depends on
the amount of memory of your system. You can change the default
number of heatmap positions. You can also set the maximum of
'weight' per heatmap position.

CSV output format:
\"weight\";\"lat\";\"lon\"
\"1001\";\"52.489\";\"4.729\"
\"883\";\"52.37\";\"4.72\"
\"868\";\"52.19\";\"4.81\"
\"862\";\"51.9\";\"4.75\"
\"791\";\"52.12\";\"4.8\"
\"759\";\"52.01\";\"4.779\"

Syntax: $scriptname

Optional parameters:
  -data <data directory>  The data files are stored in
                          '$datadirectory' by default.
  -log <log directory>    The data files are stored in
                          '$logdirectory' by default.
  -output <output         The data files are stored in
          directory>      '$outputdirectory' by default.
  -file <filename>        The output file name.
                          '$outputdatafile' by default.
  -filemask <mask>        Specify a filemask for the source data.
                          The default filemask is '$filemask'.
  -override               Override output file if exists.
                          Default is '$override'.
  -timestamp              Add timestamp to output file name.
                          Default is '$timestamp'.
  -sequencenumber         Add sequence number to output file name.
                          Default is '$sequencenumber'.
  -lon <lonitude>         Location of your antenna.
  -lat <latitude>
  -maxpositions <max      Maximum spots in the heatmap. Default is
             positions>   '$max_positions' positions.
  -maxweight <number>     Maximum position weight. The default is
                          '$max_weight'.
  -resolution <number>    Number of horizontal and vertical positions
                          in output file. Default is '$resolution',
                          which means '${resolution}x${resolution}' positions.
  -degrees <number>       To determine boundaries of area around the
                          antenna. (lat-degree <--> lat+degree) x
                          (lon-degree <--> lon+degree)
                          De default is '$degrees' degree.
  -debug                  Displays raw socket messages.
  -verbose                Displays verbose log messages.
  -help                   This help page.

note:
  The default values can be changed within the config file
  'socket30003.cfg', section [common] and section [heatmap].

Examples:
  $scriptname
  $scriptname -data /home/pi -log /var/log
  $scriptname -lat 52.1 -lon 4.1 -maxposition 50000\n\n";
	exit 0;
}
#===============================================================================
# Is the log directory writeable?
if (!-w $logdirectory) {
        LOG("The directory does not exists or you have no write permissions in log directory '$logdirectory'!","E");
        exit 1;
}
# Set log file path and name
my ($second,$day,$month,$year,$minute,$hour) = (localtime)[0,3,4,5,1,2];
my $filedate = 'heatmap-'.sprintf '%02d%02d%02d', $year-100,($month+1),$day;
$logfile = common->LOGset($logdirectory,"$filedate.log",$verbose);
#
#===============================================================================
# Resolution, Degrees & Factor
if ($resolution) {
	if ($resolution !~ /^\d{2,5}$/) {
                LOG("The resolution '$resolution' is invalid!","E");
                LOG("It should be between 10 and 99999.","E");
                exit;
        }
} else {
        $resolution = 1000;
}
if ($degrees) {
        if ($degrees !~ /^\d{1,2}(\.\d{1,9})?$/) {
                LOG("The given number of degrees '$degrees' is invalid!","E");
                LOG("It should be between 0.0001 and 99.9999 degrees.","E");
                exit;
        }
} else {
        $degrees = 5;
}
my $factor = int($resolution / ($degrees * 2));
#===============================================================================
# Max positions
if ($max_positions) {
	if (($max_positions !~ /^\d{3,6}$/) && ($max_positions > 99) && ($max_positions < 1000000)) {
		LOG("The maximum number of positions '$max_positions' is invalid!","E");
		LOG("It should be between 100 and 999999.","E");
		exit;
	}
} else {
	$max_positions = 100000;
}
LOG("There will be no more then '$max_positions' positions in the output file.","I");
#===============================================================================
if ($max_weight) {
        if (($max_weight !~ /^\d{2,4}$/) && ($max_weight > 9) && ($max_weight < 10000)) {
                LOG("The maximum position weight '$max_weight' is invalid!","E");
                LOG("It should be between 10 and 9999.","E");
                exit;
        }
} else {
        $max_weight = 1000;
}
LOG("The maximum position weight will be not more then '$max_weight'.","I");
#===============================================================================
# Is the specified directories for the output file writeable?
if (!-w $outputdirectory) {
        LOG("The directory does not exists or you have no write permissions in output directory '$outputdirectory'!","E");
        exit 1;
}
# Set output file
$outputdatafile = common->SetOutput($outputdirectory,$outputdatafile,$override,$timestamp,$sequencenumber);
#
#===============================================================================
# longitude & latitude
$longitude =~ s/,/\./ if ($longitude);
if ($longitude !~ /^[-+]?\d+(\.\d+)?$/) {
	LOG("The specified longitude '$longitude' is invalid!","E");
	exit 1;
}
$latitude  =~ s/,/\./ if ($latitude);
if ($latitude !~ /^[-+]?\d+(\.\d+)?$/) {
	LOG("The specified latitude '$latitude' is invalid!","E");
	exit 1;
}
# area around antenna
$latitude  = int($latitude  * 100000) / 100000;
$longitude = int($longitude * 100000) / 100000;
my $lat1 = int(($latitude  - $degrees) * 100000) / 100000; # most westerly latitude
my $lat2 = int(($latitude  + $degrees) * 100000) / 100000; # most easterly latitude
my $lon1 = int(($longitude - $degrees) * 100000) / 100000; # most northerly longitude
my $lon2 = int(($longitude + $degrees) * 100000) / 100000; # most southerly longitude
LOG("The resolution op the heatmap will be ${resolution}x${resolution}.","I");
LOG("The antenna latitude & longitude are: '$latitude','$longitude'.","I");
LOG("The heatmap will cover the area of $degrees degree around the antenna, which is between latitude $lat1 - $lat2 and longitude $lon1 - $lon2.","I");
#===============================================================================
# Get source data from data directory
my %data;
# Is the source directory readable?
if (!-r $datadirectory) {
	LOG("The directory does not exists or you have no read permissions in data directory '$datadirectory'!","E");
	exit 1;
}
# Set default filemask
if (!$filemask) {
	$filemask = "'dump*.txt'" ;
} else {
	$filemask ="'*$filemask*'";
}
# Find files
LOG(`find $datadirectory/ -name $filemask 2>/dev/null`);
my @files =`find $datadirectory/ -name $filemask 2>/dev/null`;
if (@files == 0) {
	LOG("No files were found in directory '$datadirectory' that matches with the $filemask filemask!","E");
	exit 1;
} else {
	LOG("The following files in directory '$datadirectory' fit with the filemask $filemask:","I");
	my @tmp;
	foreach my $file (@files) {
		chomp($file);
		next if ($file =~ /log$|pid$/i);
		LOG("  $file","I");
		push(@tmp,$file);
	}
	@files = @tmp;
	if (@files == 0) {
        	LOG("No files were found in '$datadirectory' that matches with the '$filemask' filemask!","E");
        	exit 1;
	}
}
#===============================================================================
my %pos;
my $lat;
my $lon;
open(my $outputdata, '>', "$outputdatafile") or die "Could not open file '$outputdatafile' $!";
# RFK Edit: replace the original header line with a JS array initialization
# Original line was:
# print $outputdata "\"weight\";\"lat\";\"lon\"";
print $outputdata "var addressPoints = [";
# Read input files
foreach my $filename (@files) {
	chomp($filename);
	# Read data file
	open(my $data_filehandle, '<', $filename) or die "Could not open file '$filename' $!";
	LOG("Processing file '$filename':","I");
	my $outside_area = 0;
	my $linecounter = 0;
        my @header;
        my %hdr;
	my $message="";
	while (my $line = <$data_filehandle>) {
		chomp($line);
		$linecounter++;
                # Data Header
                # First line?
                if (($linecounter == 1) || ($line =~ /hex_ident/)){
			if ($linecounter != 1) {
				$message  .= "- ".($linecounter-1)." processed.";
				LOG($message,"I");
			}
                	# Reset fileunit:
                        #%fileunit =();
                        # Does it contain header columns?
                        if ($line =~ /hex_ident/) {
				@header = ();
                        	my @unit;
                                # Header columns found!
                                my @tmp = split(/,/,$line);
                                foreach my $column (@tmp) {
                        	        if ($column =~ /^\s*([^\(]+)\(([^\)]+)\)\s*$/) {
                                		# The column name includes a unit, for example: altitude(meter)
                                        	push(@header,$1);
                                	        #$fileunit{$1} = $2;
                                        	push(@unit,"$1=$2");
                                	} else {
                                		push(@header,$column);
                                	}
                      		}
                        	$message ="  -header units:".join(",",@unit).", position $linecounter";
                      	} else {
                        	# No header columns found. Use default!
                                @header = ("hex_ident","altitude","latitude","longitude","date","time","angle","distance");
				$message ="  -default units, position $linecounter";
                        }
                       	# The file header unit information may be changed: set the units again.
                        #setunits;
                        my $columnnumber = 0;
                        # Save column name with colomn number in hash.
                        foreach my $header (@header) {
                        	$hdr{$header} = $columnnumber;
                        	$columnnumber++;
           		}
                	next if ($line =~ /hex_ident/);
                }
		# split columns into array values:
		my @col = split(/,/,$line);
		$lat = $col[$hdr{'latitude'}];
		$lon = $col[$hdr{'longitude'}];
		# remove lat/lon position that are to fare away.
		if (($lat < $lat1) || ($lat > $lat2) || ($lon < $lon1) || ($lon > $lon2)) {
			$outside_area++;
			next;
		}
		$lat = int((int(($lat - $latitude ) * $factor) / $factor + $latitude ) * 100000) / 100000;
		$lon = int((int(($lon - $longitude) * $factor) / $factor + $longitude) * 100000) / 100000;
		# count the number of time a lat/lon position was recorded:
		$pos{$lat}{$lon} = 0 if (!exists $pos{$lat}{$lon} );
		$pos{$lat}{$lon} += 1;
	}
	LOG($message."-".($linecounter-1)." processed. $outside_area positions were out side the specified area.","I");
	close($data_filehandle);
}
# Sort positions based on the number of times they occured in the flight position data.
my %sort;
foreach my $lat (keys %pos) {
	foreach my $lon (keys %{$pos{$lat}}) {
		my $number = sprintf("%08d",$pos{$lat}{$lon});
		# Save lat/lon sorted by the number of times they were recorded
		$sort{"$number,$lat,$lon"} = 1;
	}
}
LOG("Number of sorted heatmap positions: ".(keys %sort),"I");
# Get the highest :
my ($highest_weight,@rubbish)= reverse sort keys %sort;
$highest_weight =~ s/,.+,.+$//;
$highest_weight += 0;

# Get lowest weight:
my $counter = 0;
my $lowest_weight = 0;
foreach my $sort (reverse sort keys %sort) {
        my ($weight,$lat,$lon) = split(/,/,$sort);
        $counter++;
        # stop after the maximum number of heatmap positions is reached or the weight to low:
        if ($counter >= $max_positions){
		$lowest_weight = $weight;
		last;
	}
}
LOG("The highest weight is '$highest_weight' and the lowest weight is '$lowest_weight'.","I");
# Is the highest weight more then the maximum weight?
if ($max_weight > $highest_weight){
	$max_weight = $highest_weight;
} else {
	LOG("Since the highest weight is more the the max weight '$max_weight' the weight of all points will be multiplied with a factor ".($max_weight / $highest_weight).".","I");
}
# Proces the positions. Start with the positions that most occured in the flight position data.
$counter = 0;
foreach my $sort (reverse sort keys %sort) {
	my ($weight,$lat,$lon) = split(/,/,$sort);

	# (reverted to original)RFK edit: discard bottom 3% of samples to avoid cluttering the heatmap:
	# Original line was:
	last if ($weight < 1);
	# last if ( ($weight < 3) || ($weight < .03 * $highest_weight));
	$weight = int(($max_weight / $highest_weight * $weight) + ($lowest_weight * $max_weight / $highest_weight * (($highest_weight - $weight) / $highest_weight)) );
	$counter++;
	# stop after the maximum number of heatmap positions is reached:
	last if ($counter >= $max_positions);
	# print output to file:
	# Original line was:
	#	print $outputdata "\n\"$weight\";\"$lat\";\"$lon\"";
	# rfk edit
	# format is [-37.8839, 175.3745188667, "571"],
        print $outputdata "\n[$lat , $lon, \"$weight\"],";

}
# RFK Edit: write an extra line to close the JS array.
# The following 1 line was inserted:
print $outputdata "\n];";

close($outputdata);
chmod(0666,$outputdata);
LOG("$counter rows with heatmap position data processed!","I");
