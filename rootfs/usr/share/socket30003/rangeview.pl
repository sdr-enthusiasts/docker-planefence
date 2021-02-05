#!/usr/bin/perl -w
# ted.sluis@gmail.com
# Filename : rangeview.pl
#
#===============================================================================
BEGIN {
	use strict;
	use POSIX qw(strftime);
	use Time::Local;
	use Getopt::Long;
	use File::Basename;
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
my $max_altitude;
my $max_altitude_meter;
my $max_altitude_feet;
my $min_altitude;
my $number_of_directions;
my $number_of_altitudezones;
my $distanceunit;
my $altitudeunit;
my $antenna_longitude;
my $antenna_latitude;
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
        "longitude=s"=>\$antenna_longitude,
        "latitude=s"=>\$antenna_latitude,
        "distanceunit=s"=>\$distanceunit,
        "altitudeunit=s"=>\$altitudeunit,
	"max=s"=>\$max_altitude,
	"min=s"=>\$min_altitude,
	"directions=s"=>\$number_of_directions,
	"zones=s"=>\$number_of_altitudezones,
        "debug!"=>\$debug,
        "verbose!"=>\$verbose
) or exit(1);
#
$override        = "yes" if ($override);
$timestamp       = "yes" if ($timestamp);
$sequencenumber  = "yes" if ($sequencenumber);
#
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
my %setting = common->READCONFIG('socket30003.cfg',$fullscriptname);
# Use parameters & values from the 'rangeview' section. If empty or not-exists, then use from the 'common' section, otherwise script defaults.
$number_of_directions    = $number_of_directions    || $setting{'rangeview'}{'numberofdirections'}       || 1440;  # 
$number_of_altitudezones = $number_of_altitudezones || $setting{'rangeview'}{'numberofaltitudezones'}    || 24;
$max_altitude_meter = $max_altitude    || $setting{'rangeview'}{'maxaltitudemeter'} || 12000; # specified in meter
$max_altitude_feet  = $max_altitude    || $setting{'rangeview'}{'maxaltitudefeet'}  || 36000; # specified in feet
$min_altitude     = $min_altitude      || $setting{'rangeview'}{'minaltitude'}      || "0";   # specified in the output unit
$outputdatafile   = $outputdatafile    || $setting{'rangeview'}{'outputdatafile'}   || "rangeview.kml"; # KML or CSV extention
$datadirectory    = $datadirectory     || $setting{'rangeview'}{'datadirectory'}    || $setting{'common'}{'datadirectory'}   || "/tmp";
$logdirectory     = $logdirectory      || $setting{'rangeview'}{'logdirectory'}     || $setting{'common'}{'logdirectory'}    || "/tmp";
$outputdirectory  = $outputdirectory   || $setting{'rangeview'}{'outputdirectory'}  || $setting{'common'}{'outputdirectory'} || "/tmp";
$filemask         = $filemask          || $setting{'rangeview'}{'filemask'}         || $setting{'common'}{'filemask'}        || "dump*txt";
$override         = $override          || $setting{'rangeview'}{'override'}         || $setting{'common'}{'override'}        || "no";  # override output file if exists.
$timestamp        = $timestamp         || $setting{'rangeview'}{'timestamp'}        || $setting{'common'}{'timestamp'}       || "no"; # add timestamp to output file name.
$sequencenumber   = $sequencenumber    || $setting{'rangeview'}{'sequencenumber'}   || $setting{'common'}{'sequencenumber'}  || "no"; # add sequence number to output file name.
$antenna_latitude = $antenna_latitude  || $setting{'rangeview'}{'latitude'}         || $setting{'common'}{'latitude'}        || 52.085624;    # Home location, default (Utrecht, The Netherlands)
$antenna_longitude= $antenna_longitude || $setting{'rangeview'}{'longitude'}        || $setting{'common'}{'longitude'}       || 5.0890591; 
$distanceunit     =($distanceunit      || $setting{'rangeview'}{'distanceunit'}     || $setting{'common'}{'distanceunit'}    || "kilometer").','.
                   ($distanceunit      || $setting{'rangeview'}{'distanceunit'}     || $setting{'common'}{'distanceunit'}    || "kilometer"); # specify input & output unit! kilometer, nauticalmile, mile or meter
$altitudeunit     =($altitudeunit      || $setting{'rangeview'}{'altitudeunit'}     || $setting{'common'}{'altitudeunit'}    || "meter").','.
                   ($altitudeunit      || $setting{'rangeview'}{'altitudeunit'}     || $setting{'common'}{'altitudeunit'}    || "meter");     # specify input & output unit! meter or feet
#
#=============================================================================== 
# Is the log directory writeable?
if (!-w $logdirectory) {
        LOG("The log directory does not exists or you have no write permissions in '$logdirectory'!","E");
        exit 1;
}
# Set log file path and name
my ($second,$day,$month,$year,$minute,$hour) = (localtime)[0,3,4,5,1,2];
my $filedate = 'rangeview-'.sprintf '%02d%02d%02d', $year-100,($month+1),$day;
$logfile = common->LOGset($logdirectory,"$filedate.log",$verbose);
#
#=============================================================================== 
#
my %fileunit;
# defaultdistanceunit
my %distanceunit;
my $error = 0;
if ($distanceunit) {
	my @defaultdistanceunit = split(/,/,$distanceunit);
	if ($defaultdistanceunit[0] =~ /^kilometer$|^nauticalmile$|^mile$|^meter$/i) {
		$distanceunit{'in'} = lc($defaultdistanceunit[0]);
		if (defined $defaultdistanceunit[1]) {
			if ($defaultdistanceunit[1] =~ /^kilometer$|^nauticalmile$|^mile$|^meter$/i) {
				$distanceunit{'out'} = lc($defaultdistanceunit[1]);
			} else {
				$error++;
			}
		} else {
			$distanceunit{'out'} = lc($defaultdistanceunit[0]);
		}
	} else {
		$error++;
	}
} else {
	$distanceunit{'in'}  = "kilometer";
	$distanceunit{'out'} = "kilometer";
}
if ($error) {
        LOG("The default distance unit '$distanceunit' is invalid! It should be one of these: kilometer, nauticalmile, mile or meter.","E");
        LOG("If you specify two units (seperated by a comma) then the first is for incomming flight position data and the second is for the range/altitude view output file.","E");
        LOG("for example: '-distanceunit kilometer' or '-distanceunit kilometer,nauticalmile'","E");
        exit 1;
}
# defaultaltitudeunit
my %altitudeunit;
$error = 0;
if ($altitudeunit) {
	my @defaultaltitudeunit = split(/,/,$altitudeunit);
	if ($defaultaltitudeunit[0] =~ /^meter$|^feet$/i) {
		$altitudeunit{'in'} = lc($defaultaltitudeunit[0]);
		if (defined $defaultaltitudeunit[1]) {
			if ($defaultaltitudeunit[1] =~ /^meter$|^feet$/i) {
				$altitudeunit{'out'} = lc($defaultaltitudeunit[1]);
			} else {
                		$error++;
			}
		} else {
			$altitudeunit{'out'} = lc($defaultaltitudeunit[0]);
		}
	} else {
		$error++;
	}
} else {
	$altitudeunit{'in'}  = "meter";
	$altitudeunit{'out'} = "meter";
}
if ($error) {
        LOG("The default altitude unit '$altitudeunit' is invalid! It should be one of these: meter or feet.","E");
        LOG("If you specify two units (seperated by a comma) then the first is for incomming flight position data and the second is for the range/altitude view output file.","E");
        LOG("for example: '-distanceunit meter' or '-distanceunit feet,meter'","E");
        exit 1; 
}
# Get correct max altitude:
if ($altitudeunit{'out'} =~ /feet/) {
	$max_altitude = $max_altitude_feet;
} else {
	$max_altitude = $max_altitude_meter;
}

#
#===============================================================================
# Check options:
if ($help) {
	print "\nThis $scriptname script creates location data 
for a range/altitude view which can be displated in a modified 
fork of dump1090-mutobility.

The script creates two output files:
rangeview.csv) A file with location data in csv format can be 
imported in to tools like http://www.gpsvisualizer.com. 
rangeview.kml) A file with location data in kml format, which
can be imported into a modified dum1090-mutability.

Please read this post for more info:
http://discussions.flightaware.com/post180185.html#p180185

This script uses the output file(s) of the 'socket30003.pl'
script, which are by default stored in /tmp in this format:
dump1090-<hostname/ip_address>-YYMMDD.txt

It will read the files one by one and it will automaticly use 
the correct units (feet, meter, mile, nautical mile of kilometer)
for 'altitude' and 'distance' when the input files contain 
column headers with the unit type between parentheses. When 
the input files doesn't contain column headers (as produced 
by older versions of 'socket30003.pl' script) you can specify 
the units.Otherwise this script will use the default units.

The flight position data is sorted in to altitude zones. For 
each zone and for each direction the most remote location is 
saved. The most remote locations per altitude zone will be 
written to a file as a track. 

Default .kml output format:
<?xml version="1.0" encoding="UTF-8"?>
<kml xmlns="http://www.opengis.net/kml/2.2">
  <Document>
    <name>Paths</name>
    <description>Example</description>
<Style id="track-1">
      <LineStyle>
        <color>ff135beb</color>
        <width>2</width>
      </LineStyle>
      <PolyStyle>
        <color>ff135beb</color>
      </PolyStyle>
    </Style>
    <Placemark>
      <name>1</name>
      <description>00000-  500</description>
      <styleUrl>#track-1</styleUrl>
      <LineString>
        <altitudeMode>absolute</altitudeMode>
        <coordinates>
5.08865,52.00493,357
5.08808,52.00616,357
5.08722,52.00788,357
5.08667,52.00914,357
5.08604,52.01039,357
5.08560,52.01125,357
5.08518,52.01230,357
5.08461,52.01335,357
5.08400,52.01463,357
5.08345,52.01579,357
5.08293,52.01683,357
  
Optional CSV output format:  
type,new_track,name,color,trackpoint,altitudezone,destination,hex_ident,Altitude(meter),latitude,longitude,date,time,angle,distance(kilometer)  
T,1,Altitude zone 1: 00000-  500,7fffff00,1,     0,-718,484646,357,52.00493,5.08865,2017/01/10,10:46:15.738,-179.72,8  
T,0,Altitude zone 1: 00000-  500,7fffff00,2,     0,-717,484646,357,52.00616,5.08808,2017/01/10,10:46:17.164,-179.32,8  
T,0,Altitude zone 1: 00000-  500,7fffff00,3,     0,-714,484646,357,52.00788,5.08722,2017/01/10,10:46:19.740,-178.7,8  
T,0,Altitude zone 1: 00000-  500,7fffff00,4,     0,-713,484646,357,52.00914,5.08667,2017/01/10,10:46:21.041,-178.28,8  
T,0,Altitude zone 1: 00000-  500,7fffff00,5,     0,-711,484646,357,52.01039,5.08604,2017/01/10,10:46:22.622,-177.79,8  
T,0,Altitude zone 1: 00000-  500,7fffff00,6,     0,-709,484646,357,52.01125,5.08560,2017/01/10,10:46:23.892,-177.44,8  
T,0,Altitude zone 1: 00000-  500,7fffff00,7,     0,-708,484646,357,52.01230,5.08518,2017/01/10,10:46:25.244,-177.09,8  
T,0,Altitude zone 1: 00000-  500,7fffff00,8,     0,-706,484646,357,52.01335,5.08461,2017/01/10,10:46:26.625,-176.62,8  
T,0,Altitude zone 1: 00000-  500,7fffff00,9,     0,-704,484646,357,52.01463,5.08400,2017/01/10,10:46:28.031,-176.09,7  
T,0,Altitude zone 1: 00000-  500,7fffff00,10,     0,-702,484646,357,52.01579,5.08345,2017/01/10,10:46:29.475,-175.59,7  
T,0,Altitude zone 1: 00000-  500,7fffff00,11,     0,-700,484646,357,52.01683,5.08293,2017/01/10,10:46:30.940,-175.11,7  
  
Syntax: $scriptname

Optional parameters:
  -data <data directory>  The data files are stored in 
                          '$datadirectory' by default.
  -log  <data directory>  The log files are stored in 
                          '$logdirectory' by default.
  -output <output         The output file is stored in 
            directory>    '$outputdirectory' by default.
  -file <filename>        The output file name. The extention 
                          (.kml or .csv) determines the 
                          file structure!  
                          '$outputdatafile' by default.
  -filemask <mask>        Specify a filemask. 
                          The default filemask is '$filemask'.
  -override               Override output file if exists. 
                          Default is '$override'.
  -timestamp              Add timestamp to output file name. 
                          Default is '$timestamp'.
  -sequencenumber         Add sequence number to output file name. 
                          Default is '$sequencenumber'.
  -max <altitude>         Upper limit. Default is '$max_altitude $altitudeunit{'out'}'. 
                          Higher values in the input data will be skipped.
  -min <altitude>         Lower limit. Default is '$min_altitude $altitudeunit{'out'}'. 
                          Lower values in the input data will be skipped.
  -directions <number>    Number of compass direction (pie slices). 
                          Minimal 8, maximal 7200. Default = '$number_of_directions'.
  -zones <number>         Number of altitude zones. 
                          Minimal 1, maximum 99. 
                          Default = '$number_of_altitudezones'.
  -lon <lonitude>         Location of your antenna.
  -lat <latitude>          
  -distanceunit <unit>,[<unit>] 
                          Type of unit: kilometer, nauticalmile,
                          mile or meter. First unit is for the 
                          incoming source, the file(s) with flight
                          positions. The second unit is for the 
                          output file. No unit means it is the 
                          same as incoming.
                          Default distance unit's are: 
                          '$distanceunit'.
  -altitudeunit <unit>[,<unit>] 
                          Type of unit: feet or meter. First unit
                          is for the incoming source, the file(s) 
                          with flight positions. The second unit 
                          is for the output file. No unit means it 
                          is the same as incoming. 
                          Default altitude unit's are: 
                          '$altitudeunit'.
  -debug                  Displays raw socket messages.
  -verbose                Displays verbose log messages.
  -help                   This help page.

notes: 
  - The default values can be changed within the config file 'socket30003.cfg'.
  - The source units will be overruled in case the input file header contains unit information.

Examples:
  $scriptname 
  $scriptname -distanceunit kilometer,nauticalmile -altitudeunit meter,feet
  $scriptname -data /home/pi/data -log /home/pi/log -output /home/pi/result \n\n";
	exit 0;
}
#=============================================================================== 
print "The altitude will be converted from '$altitudeunit{'in'}' to '$altitudeunit{'out'}'.\n";
print "The distance will be converted from '$distanceunit{'in'}' to '$distanceunit{'out'}.\n";
my %convertalt;
my %convertdis;
#===============================================================================
# Set unit for altitude and distance
sub setunits(@) {
	# altitude unit:
	$convertalt{'in'}  = 1              if ($altitudeunit{'in'}  eq "meter");
	$convertalt{'out'} = 1              if ($altitudeunit{'out'} eq "meter");
	$convertalt{'in'}  = 0.3048         if ($altitudeunit{'in'}  eq "feet");
	$convertalt{'out'} = 3.2808399      if ($altitudeunit{'out'} eq "feet");
	# altitude unit is overruled in case the input file header contains unit information:
	$convertalt{'in'}  = 1              if ((exists $fileunit{'altitude'}) && ($fileunit{'altitude'} eq "meter"));
	$convertalt{'in'}  = 0.3048	    if ((exists $fileunit{'altitude'}) && ($fileunit{'altitude'} eq "feet"));
	# distance
	$convertdis{'in'}  = 1              if ($distanceunit{'in'}  eq "meter");
	$convertdis{'out'} = 1              if ($distanceunit{'out'} eq "meter");
	$convertdis{'in'}  = 1609.344       if ($distanceunit{'in'}  eq "mile");
	$convertdis{'out'} = 0.000621371192 if ($distanceunit{'out'} eq "mile");
	$convertdis{'in'}  = 1852           if ($distanceunit{'in'}  eq "nauticalmile");
	$convertdis{'out'} = 0.000539956803 if ($distanceunit{'out'} eq "nauticalmile");
	$convertdis{'in'}  = 1000           if ($distanceunit{'in'}  eq "kilometer");
	$convertdis{'out'} = 0.001          if ($distanceunit{'out'} eq "kilometer");
	# distance unit is overruled in case the input file header contains unit information:
	$convertdis{'in'}  = 1              if ((exists $fileunit{'distance'}) && ($fileunit{'distance'} eq "meter"));
	$convertdis{'in'}  = 1609.344       if ((exists $fileunit{'distance'}) && ($fileunit{'distance'} eq "mile"));
	$convertdis{'in'}  = 1852           if ((exists $fileunit{'distance'}) && ($fileunit{'distance'} eq "nauticalmile"));
	$convertdis{'in'}  = 1000           if ((exists $fileunit{'distance'}) && ($fileunit{'distance'} eq "kilometer"));
}
setunits;
# convert altitude to the correct unit:
sub alt(@) {
	my $altitude  = shift;
	my $altitude_in_meters = $convertalt{'in'}  * $altitude;
	my $result =         int($convertalt{'out'} * $altitude_in_meters);
	return $result;
}
# convert distance to the correct unit:
sub dis(@) {
	my $distance = shift;
	my $distance_in_meters = $convertdis{'in'}  * $distance;
	my $result =         int($convertdis{'out'} * $distance_in_meters);
}
#
#=============================================================================== 
# Is the specified directories for the output file writeable? 
if (!-w $outputdirectory) {
        LOG("The output directory does not exists or you have no write permissions in '$datadirectory'!","E");
        exit 1;
}
# check file name extention
if ($outputdatafile =~ /\.csv$|\.kml/i) {
	# Set output file
	$outputdatafile = common->SetOutput($outputdirectory,$outputdatafile,$override,$timestamp,$sequencenumber);
} else {
	LOG("The output file name '$outputdatafile' is invalid! It should have a .kml or .csv extention!","E");
	exit 1;
}
#===============================================================================
$error=0;
if ((($max_altitude) && ($max_altitude !~ /^\d+$/)) || ($max_altitude > (20000 * $convertalt{'out'})) || ($max_altitude <= $min_altitude)) {
	LOG("The maximum altitude ($max_altitude $altitudeunit{'out'}) is not valid! It should be at least as high as the minium altitude ($min_altitude $altitudeunit{'out'}), but not higher than ".(20000 * $convertalt{'out'})." $altitudeunit{'out'}!","E");
	$error++;
} else {
	LOG("The maximum altitude is $max_altitude $altitudeunit{'out'}.","I");
}
if ((($min_altitude) && ($min_altitude !~ /^\d+$/)) || ($min_altitude < 0) || ($min_altitude >= $max_altitude)) {
	LOG("The minium altitude ($min_altitude $altitudeunit{'out'}) is not valid! It should be less than the maximum altitude ($max_altitude $altitudeunit{'out'}), but not less than 0 $altitudeunit{'out'}!","E");
	$error++;
} else {
 	LOG("The minimal altitude is $min_altitude $altitudeunit{'out'}.","I");
}
if ((($number_of_directions) && ($number_of_directions !~ /^\d+$/)) || ($number_of_directions < 8) || ($number_of_directions > 7200)) {
	LOG("The number of compass directions ($number_of_directions) is invalid! It should be at least 8 and less then 7200.","E");
	$error++;
} else {
	LOG("The number of compass directions (pie slices) is $number_of_directions.","I");
}
if ((($number_of_altitudezones) &&($number_of_altitudezones !~ /^\d+$/)) || ($number_of_altitudezones < 1) || ($number_of_altitudezones > 99)) {
	LOG("The number of altitude zones ($number_of_altitudezones) is invalid! It should be at least 1 and less than 100.","E");
} else {
	LOG("The number of altitude zones is $number_of_altitudezones.","I");
}
if ($error > 0) {
	exit 1;
}
# longitude & latitude
$antenna_longitude =~ s/,/\./ if ($antenna_longitude);
if ($antenna_longitude !~ /^[-+]?\d+(\.\d+)?$/) {
        LOG("The specified longitude '$antenna_longitude' is invalid!","E");
        exit 1;
}
$antenna_latitude =~ s/,/\./ if ($antenna_latitude);
if ($antenna_latitude !~ /^[-+]?\d+(\.\d+)?$/) {
        LOG("The specified latitude '$antenna_latitude' is invalid!","E");
        exit 1;
}
LOG("The latitude/longitude location of the antenna is: $antenna_latitude,$antenna_longitude.","I");
#
#===============================================================================
my $diff_altitude  = $max_altitude - $min_altitude;
my $zone_altitude  = int($diff_altitude / $number_of_altitudezones);
LOG("An altitude zone is $zone_altitude $altitudeunit{'out'}.","I");
#
#=============================================================================== 
# Get source file names
my @files = common->GetSourceData($datadirectory,$filemask);
#===============================================================================
my %data;
my $filecounter=0;
my $positioncounter=0;
my %positionperzonecounter;
my %positionperdirectioncounter;
my $position;
# Read input files
foreach my $filename (@files) {
	LOG("processing '$filename':","I");
	$filecounter++;
	chomp($filename);
	# Read data file
	open(my $data_filehandle, '<', $filename) or die "Could not open file '$filename' $!";
	my $linecounter = 0;
	my @header; 
	my %hdr;
	my $message;
	while (my $line = <$data_filehandle>) {
		chomp($line);
		$linecounter++;
		# Data Header
		# First line? 
		if (($linecounter == 1) || ($line =~ /hex_ident/)){
			if ($linecounter != 1){
				$message .= "- ".($linecounter-1)." processed.";
				LOG($message,"I");
			}
			# Reset fileunit:
			%fileunit =();
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
						$fileunit{$1} = $2;
						push(@unit,"$1=$2");
					} else {
						push(@header,$column);
					}
				}
				$message = "  -header units:".join(",",@unit).", position $linecounter";
			} else {
				# No header columns found. Use default!
				@header = ("hex_ident","altitude","latitude","longitude","date","time","angle","distance");
				$message = "  -default units:altitude=$altitudeunit{'in'},distance=$distanceunit{'in'}, position $linecounter";
			}
			# The file header unit information may be changed: set the units again.
			setunits;
			my $columnnumber = 0;
			# Save column name with colomn number in hash.
			foreach my $header (@header) {
			        $hdr{$header} = $columnnumber;
		        	$columnnumber++;
			}
			next if ($line =~ /hex_ident/);
		}
		# split line in to columns.
		my @col = split(/,/,$line);
		$position++;
		my $altitude = alt($col[$hdr{'altitude'}]);
		my $distance = dis($col[$hdr{'distance'}]);
		# Remove any invalid position bigger than 600km
		next if ($distance > (600000 * $convertdis{'out'}));
		# Skip lower then min_altitude.
		next if ($altitude < $min_altitude);
		# Skip higher then max_altitude is the highest zone:
		next if ($altitude > $max_altitude); 
		# Calculate the altitude zone and direction zone
		my $altitude_zone  = sprintf("% 6d",int($altitude / $zone_altitude) * $zone_altitude);
		my $direction_zone = sprintf("% 4d",int($col[$hdr{'angle'}] / 360 * $number_of_directions));
		# Update the counters for statictics
		$positioncounter++;
		$positionperzonecounter{$altitude_zone} = 0 if (!exists $positionperzonecounter{$altitude_zone});
		$positionperzonecounter{$altitude_zone}++;
		$positionperdirectioncounter{$altitude_zone}{$direction_zone} = 0 if (! exists $positionperdirectioncounter{$altitude_zone}{$direction_zone});
		$positionperdirectioncounter{$altitude_zone}{$direction_zone}++;
		# Save position if it is the most fare away location for it's altitude zone and direction zoe:
		if ((!exists $data{$altitude_zone}||(!exists $data{$altitude_zone}{$direction_zone})||($data{$altitude_zone}{$direction_zone}{'distance'} < $col[$hdr{'distance'}]))) {
			$data{$altitude_zone}{$direction_zone}{'distance'}   = int($distance * 100) / 100;
                        $data{$altitude_zone}{$direction_zone}{'hex_ident'}  = $col[$hdr{'hex_ident'}];
                        $data{$altitude_zone}{$direction_zone}{'altitude'}   = int($altitude);
                        $data{$altitude_zone}{$direction_zone}{'latitude'}   = $col[$hdr{'latitude'}];
                        $data{$altitude_zone}{$direction_zone}{'longitude'}  = $col[$hdr{'longitude'}];
                        $data{$altitude_zone}{$direction_zone}{'date'}       = $col[$hdr{'date'}];
                        $data{$altitude_zone}{$direction_zone}{'time'}       = $col[$hdr{'time'}];
                        $data{$altitude_zone}{$direction_zone}{'angle'}      = int($col[$hdr{'angle'}] * 100) / 100;

		}
	}
	close($data_filehandle);
	$message .= "-".($linecounter-1).". processed.";
	LOG($message,"I");
}
LOG("Number of files read: $filecounter","I");
LOG("Number of position processed: $position and positions within range processed: $positioncounter","I");
#===============================================================================
# convert hsl colors to bgr colors
sub hsl_to_bgr(@) {
    	my ($h, $s, $l) = @_;
    	my ($r, $g, $b);
    	if ($s == 0){
    		$r = $g = $b = $l;
    	} else {
   		sub hue2rgb(@){
            		my ($p, $q, $t) = @_;
            		while ($t < 0) { $t += 1;                                   }
            		while ($t > 1) { $t -= 1;                                   }
            		if ($t < (1/6))  { return $p + ($q - $p) * 6 * $t;            }
            		if ($t < (1/2))  { return $q;                                 }
            		if ($t < (2/3))  { return $p + ($q - $p) * (2/3 - $t) * 6;    }
            		return $p;
        	}
        	my $q = $l < 0.5 ? $l * (1 + $s) : $l + $s - $l * $s;
        	my $p = 2 * $l - $q;
        	$r = hue2rgb($p, $q, $h + 1/3);
        	$g = hue2rgb($p, $q, $h);
        	$b = hue2rgb($p, $q, $h - 1/3);
    	}
    	$r = sprintf("%x",int($r * 255));
	$g = sprintf("%x",int($g * 255)); 
	$b = sprintf("%x",int($b * 255));
	return $b.$g.$r;
}
#================================================================================
# 
my @zone;
foreach my $altitude_zone (sort {$a<=>$b} keys %data) {
	foreach my $dz (0..$number_of_directions) {
		$direction_zone = sprintf("% 4d",$dz);
		foreach my $previous_altitude_zone (@zone) {
			# Higher altitude zones reache atleast as far as the lower altitude zones.
			if ((exists $data{$previous_altitude_zone}) && (exists $data{$previous_altitude_zone}{$direction_zone}) && 
			    ((!exists $data{$altitude_zone}{$direction_zone}) || 
			     ($data{$previous_altitude_zone}{$direction_zone}{'distance'} > $data{$altitude_zone}{$direction_zone}{'distance'}))) {
				foreach my $header ("hex_ident","altitude","latitude","longitude","date","time","angle","distance") {
                        		$data{$altitude_zone}{$direction_zone}{$header} = $data{$previous_altitude_zone}{$direction_zone}{$header};
				}
				
			}
		}
	}
	# Save previous zones
	push(@zone,$altitude_zone);
}
#================================================================================
my @color = ("7f0000ff","7fffff00","7fff0033","7f00cc00","7fff00ff","7fff6600","7f660099","7f00ffff");
my $data_filehandle;
my $kml_filehandle;
my $trackpoint=0;
my $track=0;
my $newtrack;
if ($outputdatafile =~ /csv$/i) {
	open($data_filehandle, '>',"$outputdatafile") or die "Unable to open '$outputdatafile'!\n";
	print $data_filehandle "type,new_track,name,color,trackpoint,altitudezone,destination,hex_ident,Altitude($altitudeunit{'out'}),latitude,longitude,date,time,angle,distance($distanceunit{'out'})\n";
} else {
	open($kml_filehandle, '>',"$outputdatafile") or die "Unable to open '$outputdatafile'!\n";
	print $kml_filehandle "<?xml version=\"1.0\" encoding=\"UTF-8\"?>
<kml xmlns=\"http://www.opengis.net/kml/2.2\">
  <Document>
    <name>Paths</name>
    <description>Example</description>\n";
}
foreach my $altitude_zone (sort {$a<=>$b} keys %data) {
	$track++;
        # convert altitude to feet:
        my $altitude_feet = $altitude_zone / $convertalt{'out'} * 3.2808399 / 1.8;
	my $s = 85;
	my $l = 50;
	my $h = 20;
	my @val = (20,140,300);
	my @alt = (2000,10000,40000);
	foreach my $index (0..$#alt) {
		if ($altitude_feet > $alt[$index]) {
			if ($index == 2) {
				$h = $val[$index];
			} else {
				$h = ($val[$index] + ($val[$index+1] - $val[$index]) * ($altitude_feet - $alt[$index]) / ($alt[$index+1] - $alt[$index]));
			}
			last;
		}
	}
	if ($h < 0) {$h = ($h % 360) + 360;} elsif ($h >= 360) {$h = $h % 360;}
        if ($s < 5) {$s = 5;} elsif ($s > 95) {$s = 95;}
        if ($l < 5) {$l = 5;} elsif ($l > 95) {$l = 95;}
	my $kml_color = "ff".hsl_to_bgr($h/360,$s/100,$l/100);
	# Determine color
	my $colornumber = $track;
	while ($colornumber > 7) {
		$colornumber = $colornumber - 8;
	}
	my $alt_zone_name = sprintf("%05d-%5d",$altitude_zone,($altitude_zone + $zone_altitude));
	my $positionperzonecounter = sprintf("% 9d",$positionperzonecounter{$altitude_zone});
	my $tracknumber = sprintf("% 2d",$track);
	$newtrack = 1;
	my $min_positions_per_direction =0;
	my $max_positions_per_direction =0;
	print $kml_filehandle "<Style id=\"track-$track\">
      <LineStyle>
        <color>$kml_color</color>
        <width>2</width>
      </LineStyle>
      <PolyStyle>
        <color>$kml_color</color>
      </PolyStyle>
    </Style>
    <Placemark>
      <name>$track</name>
      <description>$alt_zone_name</description>
      <styleUrl>#track-$track</styleUrl>
      <LineString>
        <altitudeMode>absolute</altitudeMode>
        <coordinates>\n" if ($outputdatafile =~ /kml$/i);
	foreach my $direction_zone (sort {$a<=>$b} keys %{$data{$altitude_zone}}) {
		my @row;
		my @kml;
		foreach my $header ("hex_ident","altitude","latitude","longitude","date","time","angle","distance") {
			push(@row,$data{$altitude_zone}{$direction_zone}{$header});
		}
		$trackpoint++;
		if ($outputdatafile =~ /kml$/i) {
	  		print $kml_filehandle "$data{$altitude_zone}{$direction_zone}{'longitude'},$data{$altitude_zone}{$direction_zone}{'latitude'},$data{$altitude_zone}{$direction_zone}{'altitude'}\n";	
		} else {
			print $data_filehandle "T,$newtrack,Altitude zone $track: $alt_zone_name,$color[$colornumber],$trackpoint,$altitude_zone,$direction_zone,".join(",",@row)."\n";
		}
		$newtrack = 0;
		$positionperdirectioncounter{$altitude_zone}{$direction_zone} = 0 if (! exists $positionperdirectioncounter{$altitude_zone}{$direction_zone});
		$min_positions_per_direction = $positionperdirectioncounter{$altitude_zone}{$direction_zone} if ($positionperdirectioncounter{$altitude_zone}{$direction_zone} < $max_positions_per_direction);
		$max_positions_per_direction = $positionperdirectioncounter{$altitude_zone}{$direction_zone} if ($positionperdirectioncounter{$altitude_zone}{$direction_zone} > $max_positions_per_direction);
	}
	print $kml_filehandle "</coordinates>
      </LineString>
    </Placemark>\n"  if ($outputdatafile =~ /kml$/i);
	my $real_number_of_directions = scalar keys %{$positionperdirectioncounter{$altitude_zone}};
	my $avarage_positions_per_direction = sprintf("% 6d",($positionperzonecounter{$altitude_zone} / $number_of_directions));
	my $avarage_positions_per_real_direction =sprintf("% 6d",($positionperzonecounter{$altitude_zone} / $real_number_of_directions));
	my $line = sprintf("% 3d,Altitude zone:% 6d-% 6d,Directions:% 5d/% 5d,Positions processed:% 10d,Positions processed per direction: min:% 6d,max:% 6d,avg:% 6d,real avg:% 6d",$tracknumber,$altitude_zone,($altitude_zone + $zone_altitude-1),($real_number_of_directions+1),$number_of_directions,$positionperzonecounter{$altitude_zone},$min_positions_per_direction,$max_positions_per_direction,$avarage_positions_per_direction,$avarage_positions_per_real_direction);
	LOG($line,"I");
}
print $kml_filehandle "</Document>
</kml>\n" if ($outputdatafile =~ /kml$/i);
close $outputdatafile;

