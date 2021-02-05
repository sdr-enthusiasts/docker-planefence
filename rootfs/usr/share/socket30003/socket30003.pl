#!/usr/bin/perl -w
# ted.sluis@gmail.com
# Filename : socket30003.pl
#
#===============================================================================
# This script reads data from a dump1090 instance using TCP 30003 port stream  and writes 
# longitude, latitude, altitude, hex_indent, flight number, ground speed, squawk, 
# direction, date and time to a text file (comma serperated).
# The script also calculates the angle and distance relative to location of the antenna.
#===============================================================================
# Down here are the fields that are served in the messages by dump1090 over port 30003:
# Note: not all fields are filled with data.
#
# Field			Description
# message_type		See MessageType.
# transmission_type	See TransmissionType.
# session_id		String. Database session record number.
# aircraft_id		String. Database aircraft record number.
# hex_ident		String. 24-bit ICACO ID, in hex.
# flight_id		String. Database flight record number.
# generated_date	String. Date the message was generated.
# generated_time	String. Time the message was generated.
# logged_date		String. Date the message was logged.
# logged_time		String. Time the message was logged.
# callsign		String. Eight character flight ID or callsign.
# altitude		Integer. Mode C Altitude relative to 1013 mb (29.92" Hg).
# ground_speed		Integer. Speed over ground.
# track			Integer. Ground track angle.
# lat			Float. Latitude.
# lon			Float. Longitude
# vertical_rate		Integer. Climb rate.
# squawk		String. Assigned Mode A squawk code.
# alert			Boolean. Flag to indicate that squawk has changed.
# emergency		Boolean. Flag to indicate emergency code has been set.
# spi			Boolean. Flag to indicate Special Position Indicator has been set.
# is_on_ground		Boolean. Flag to indicate ground squat switch is active.
#
# MessageType
# There are 6 types of SBS-1 messages represented by the MessageType enum:
# Enum	Value
# SELECTION_CHANGE	"SEL"
# NEW_ID		"ID"
# NEW_AIRCRAFT		"AIR"
# STATUS_AIRCRAFT	"STA"
# CLICK			"CLK"
# TRANSMISSION		"MSG"
# SELECTION_CHANGE, NEW_ID, NEW_AIRCRAFT, STATUS_CHANGE, and CLK indicate changes in the state of the SBS-1 software and aren't typically used by other systems.
#
# TRANSMISSION messages contain information sent by aircraft.
# TransmissionType
# There are 8 subtypes of transmission messages, specified by the TransmissionType enum:
# Enum	Value	Description	Spec
# ES_IDENT_AND_CATEGORY	1	ES identification and category	DF17 BDS 0,8
# ES_SURFACE_POS	2	ES surface position message	DF17 BDS 0,6
# ES_AIRBORNE_POS	3	ES airborne position message	DF17 BDS 0,5
# ES_AIRBORNE_VEL	4	ES airborne velocity message	DF17 BDS 0,9
# SURVEILLANCE_ALT	5	Surveillance alt message	DF4, DF20
# SURVEILLANCE_ID	6	Surveillance ID message		DF5, DF21
# AIR_TO_AIR		7	Air-to-air message		DF16
# ALL_CALL_REPLY	8	All call reply			DF11
# Only ES_SURFACE_POS and ES_AIRBORNE_POS transmissions will have position (latitude and longitude) information.
#
#===============================================================================
BEGIN { 
	use strict;
	use POSIX qw(strftime);
	use Time::Local;
	use Socket; # For constants like AF_INET and SOCK_STREAM
	use Getopt::Long;
	use File::Basename;
	use Cwd 'abs_path';
	our $scriptname  = basename($0);
	our $fullscriptname = abs_path($0);
	use lib dirname (__FILE__);
	use common;
}
#===============================================================================
my $logfile ="";
my $message;
my $epochtime = time();
my $defaultdistanceunit;
my $defaultaltitudeunit;
my $defaultspeedunit;
#===============================================================================
# Get options
my $restart;
my $stop;
my $status;
my $help;
my $datadirectory;
my $logdirectory;
my $piddirectory;
my $peerhost;
my $time_message_margin;
my $lon;
my $lat;
my $nopositions;
my $debug = 0;
my $verbose = 0;
GetOptions(
	"restart!"=>\$restart,
	"stop!"=>\$stop,
	"status!"=>\$status,
	"help!"=>\$help,
	"distanceunit=s"=>\$defaultdistanceunit,
	"altitudeunit=s"=>\$defaultaltitudeunit,
	"speedunit=s"=>\$defaultspeedunit,
	"nopositions!"=>\$nopositions,
	"data=s"=>\$datadirectory,
	"log=s"=>\$logdirectory,
	"pid=s"=>\$piddirectory,
	"peer=s"=>\$peerhost,
	"msgmargin=s"=>\$time_message_margin,
	"longitude=s"=>\$lon,
	"latitude=s"=>\$lat,
	"debug!"=>\$debug,
	"verbose!"=>\$verbose
) or exit(1);
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
# Ctrl-C interupt handler
my $interrupted = 0;
$SIG{'INT'} = \&intHandler;
# 
sub intHandler {
	# Someone pressed Ctrl-C
	if (($message)||(($epochtime+2) >time)) {
		LOG("You pressed CTRL-C. Do you want to exit? (y/n)","W");
        	my $answer = <STDIN>;
        	if ($answer =~ /^y$/i) {
    			$interrupted = "The script was interrupted by CTRL-C!";
		} else {
			LOG("'$scriptname' continues...","I");
		}
	} else {
		LOG("You pressed CTRL-C. $scriptname' is interrupted!","W");
		exit 1;
	}
}
#
#===============================================================================
# Read settings from config file
my %setting = common->READCONFIG('socket30003.cfg',$fullscriptname);
my $PEER_HOST             = $setting{'socket30003'}{'PEER_HOST'}           || '127.0.0.1';   # The IP address or hostname of the DUMP1090 host. A Dump1090 on a local host can be addressed with 127.0.0.1
my $TIME_MESSAGE_MARGIN   = $setting{'socket30003'}{'TIME_MESSAGE_MARGIN'} || 10;            # max acceptable margin between messages in milliseconds.
my $defaultdatadirectory  = $setting{'socket30003'}{'datadirectory'}       || $setting{'common'}{'datadirectory'} || "/tmp";
my $defaultlogdirectory   = $setting{'socket30003'}{'logdirectory'}        || $setting{'common'}{'logdirectory'}  || "/tmp";
my $defaultpiddirectory   = $setting{'socket30003'}{'piddirectory'}        || $setting{'common'}{'piddirectory'}  || "/tmp";
my $latitude              = $setting{'socket30003'}{'latitude'}            || $setting{'common'}{'latitude'}      || 52.085624; # Home location, default (Utrecht, The Netherlands)
my $longitude             = $setting{'socket30003'}{'longitude'}           || $setting{'common'}{'longitude'}     || 5.0890591;     
   $defaultdistanceunit   = $defaultdistanceunit || $setting{'socket30003'}{'distanceunit'} || $setting{'common'}{'distanceunit'}  || "kilometer";   # kilometer, nauticalmile, mile or meter.
   $defaultaltitudeunit   = $defaultaltitudeunit || $setting{'socket30003'}{'altitudeunit'} || $setting{'common'}{'altitudeunit'}  || "meter";       # meter or feet.
   $defaultspeedunit      = $defaultspeedunit    || $setting{'socket30003'}{'speedunit'}    || $setting{'common'}{'speedunit'}     || "kilometerph"; # kilometerph, knotph or mileph (ph = per hour). 
#
#===============================================================================
# Check options:
if ($help) {
	print "
This $scriptname script can retrieve flight data (like lat, lon and alt) 
from a dump1090 host using port 30003 and calcutates the distance and 
angle between the antenna and the plane. It will store these values in an 
output file in csv format (seperated by commas).

This script can run several times simultaneously on one host retrieving
data from multiple dump1090 instances on different hosts. Each instance 
can use the same directories, but they all have their own data, log and 
pid files. And every day the script will create a new data and log file.

A data files contain column headers (with the names of the columns). 
Columns headers like 'altitude', 'distance' and 'ground_speed' also contain
their unit between parentheses, for example '3520(feet)' or '12,3(kilometer)'.
This makes it more easy to parse the columns when using this data in other
scripts. Every time the script is (re)started a header wiil be written 
in to the data file. This way it is possible to switch a unit, for 
example from 'meter' to 'kilometer', and other scripts will still be able
to determine the correct unit type.

By default the position data, log files and pid file(s) will be stored in this format:
  dump1090-<hostname/ip_address>-<YYMMDD>.txt
  dump1090-<hostname/ip_address>-<YYMMDD>.log
  dump1090-<hostname/ip_address>.pid

CSV output format:
hex_ident,altitude(meter),latitude,longitude,date,time,angle,distance(kilometer),squawk,ground_speed(kilometerph),track,callsign
484CB8,3906,52.24399,5.25500,2017/01/09,16:35:02.113,45.11,20.93,0141,659,93,KLM1833 
406D77,11575,51.09984,7.73237,2017/01/09,16:35:02.129,111.12,212.94,,,,BAW256  
4CA1D4,11270,53.11666,6.02148,2017/01/09,16:35:03.464,40.85,130.79,,842,81,RYR89VN 
4B1A1B,3426,51.86971,4.14556,2017/01/09,16:35:03.489,-103.38,68.93,1000,548,352,EZS85TP 
4CA79D,11575,51.95681,4.17119,2017/01/09,16:35:03.489,-98.28,64.41,1366,775,263,RYR43FH 

The script can be lauched as a background process. It can be stopped by
using the -stop parameter or by removing the pid file. When it not 
running as a background process, it can also be stopped by pressing 
CTRL-C. The script will write the current data and log entries to the 
filesystem before exiting...

More info at:
http://discussions.flightaware.com/post180185.html#p180185

Syntax: $scriptname

Optional parameters:
	-peer <peer host>		A dump1090 hostname or IP address. 
					De default is the localhost, $PEER_HOST.
	-restart			Restart the script.
	-stop				Stop a running script.
	-status				Display status.
	-data <data directory>		The data files are stored in $defaultdatadirectory by default.
	-log  <log directory>		The log file is stored in $defaultlogdirectory by default.
	-pid  <pid directory>		The pid file is stored in $defaultpiddirectory by default.
	-msgmargin <max message margin> The max message margin. The default is $TIME_MESSAGE_MARGIN ms.
	-lon <lonitude>			Location of your antenna.
	-lat <latitude>
	-distanceunit <unit>            Type of unit for distance: kilometer, 
	                                nauticalmile, mile or meter
	                                Default distance unit is $defaultdistanceunit.
	-altitudeunit <unit>	        Type of unit for altitude: meter or feet.
					Default altitude unit is $defaultaltitudeunit.
	-speedunit <unit>		Type of unit for ground speed.
					Default speed unit is $defaultspeedunit.
        -nopositions                    Does not display the number of position while
	                                running interactive (launched from commandline).
	-debug                          Displays raw socket messages.
	-verbose                        Displays verbose log messages.
	-help				This help page.

Notes: 
        - To launch it as a background process, add '&' or run it from crontab:
          0 * * * * $fullscriptname
          (This command checks if it ran every hour and relauch it if nessesary.)
        - The default values can be changed within the config file 'socket30003.cfg',
          section [common] and/or [socker30003].
  
Examples:
	$scriptname 
	$scriptname -log /var/log -data /home/pi -pid /var/run -restart &
	$scriptname -peer 192.168.1.10 -nopositions -distanceunit nauticalmile -altitudeunit feet &
	$scriptname -peer 192.168.1.10 -stop

Pay attention: to stop an instance: Don't forget to specify the same peer host.\n\n";
	exit;
}
# defaultdestinationunit
if ($defaultdistanceunit) {
	if ($defaultdistanceunit =~ /^kilometer$|^nauticalmile$|^mile$|^meter$/i) {
		$defaultdistanceunit = lc($defaultdistanceunit);
	} else {
		LOG("The default distance unit '$defaultdistanceunit' is invalid! It should be one of these: kilometer, nauticalmile, mile or meter.","E");
		exit 1;
	}
} else { 
	$defaultdistanceunit = "kilometer";
} 
# defaultaltitudeunit
if ($defaultaltitudeunit) {
	if ($defaultaltitudeunit =~ /^meter$|^feet$/i) {
		$defaultaltitudeunit = lc($defaultaltitudeunit);
	} else {
		LOG("The default altitude unit '$defaultaltitudeunit' is invalid! It should be one of these: meter or feet.","E");
		exit 1;
	}
} else { 
	$defaultaltitudeunit = "meter";
}
# defaultspeedunit
if ($defaultspeedunit) {
	if ($defaultspeedunit =~ /^kilometerph$|^mileph$|^knotph$/i) {
                $defaultspeedunit = lc($defaultspeedunit);
	} else {
		LOG("The default speed unit '$defaultspeedunit' is invalid! It should be one of these: kilometerph, mileph or knotph (ph = per hour).","E");
                exit 1;
	}
} else {
	$defaultspeedunit = "kilometer";
}
LOG("Using the unit '$defaultdistanceunit' for the distance, '$defaultaltitudeunit' for the altitude and '$defaultspeedunit' for the speed.","I");
#
# Compose filedate
sub filedate(@) {
	my $hostalias = shift;
	my ($second,$day,$month,$year,$minute) = (localtime)[0,3,4,5,1];
	my $filedate = 'dump1090-'.$hostalias.'-'.sprintf '%02d%02d%02d', $year-100,($month+1),$day;
}
#
# Are the specified directories for data, log and pid file writeable?
$datadirectory = $defaultdatadirectory if (!$datadirectory);
if (!-w $datadirectory) {
	LOG("You have no write permissions in data directory '$datadirectory'!","E");
	exit 1;
}
$logdirectory = $defaultlogdirectory if (!$logdirectory);
if (!-w $logdirectory) {
        LOG("You have no write permissions in log directory '$logdirectory'!","E");
        exit 1;
}
$piddirectory = $defaultpiddirectory if (!$piddirectory);
if (!-w $logdirectory) {
        LOG("You have no write permissions in pid directory '$piddirectory'!","E");
        exit 1;
}
# Was a hostname specified?
$PEER_HOST = $peerhost if ($peerhost);
# Test peer host:
my @ping =`ping -w 4 -c 1 $PEER_HOST`;
my $result;
foreach my $output (@ping) {
	# rtt min/avg/max/mdev = 162.207/162.207/162.207/0.000 ms
        if ($output =~ /=\s*\d{1,4}\.\d{1,4}\/\d{1,4}\.\d{1,4}\/\d{1,4}\.\d{1,4}\/\d{1,4}\.\d{1,4}\s*ms/) {
		$result = "ok";	
	}
}
if (!$result) {
	LOG("Unable to connect to peer host '$PEER_HOST'!","E");
	exit 1;
} else {
	LOG("Trying to connect to peer host '$PEER_HOST'...","I");
}
# Was a time message margin specified?
$TIME_MESSAGE_MARGIN = $time_message_margin if ($time_message_margin);
if (($TIME_MESSAGE_MARGIN < 1) || ($TIME_MESSAGE_MARGIN > 2000)) {
	LOG("The specified 'message margin' ($TIME_MESSAGE_MARGIN) is out of range!","E");
	LOG("Try something between '1' and '2000' milliseconds! The default is 10ms","E");
	exit 1;
}
# longitude & latitude
$longitude = $lon if ($lon);
$longitude =~ s/,/\./ if ($longitude);
if ($longitude !~ /^[-+]?\d+(\.\d+)?$/) {
	LOG("The specified longitude '$longitude' is invalid!","E");
	exit 1;
}
$latitude = $lat if ($lat);
$latitude =~ s/,/\./ if ($latitude);
if ($latitude !~ /^[-+]?\d+(\.\d+)?$/) {
	LOG("The specified latitude '$latitude' is invalid!","E");
	exit 1;
}
LOG("The antenna latitude & longitude are: '$latitude','$longitude'","I");
#
#===============================================================================
# Convert epoch time to YYYY-MM-DD/HH:MM:SS format
sub epoch2date (@) {
	my $epoch = shift;
	my $datestring = strftime "%Y-%m-%d/%H:%M:%S", localtime($epoch);
	return $datestring;
}
#
#===============================================================================
# Calculate angle and distance between two coordinates
#
# Calculate pi
my $pi = atan2(1,1) * 4;
#
# Calculate angle between 2 coordinates relative to the north pole.
# 0 = north, -90 = west, 90 = east, (-/+)180 = south
sub angle(@) {
	my ($lat1,$lon1,$lat2,$lon2) = @_;
	my $dlat = $lat2 - $lat1;
    	my $dlon = $lon2 - $lon1;
    	my $y = sin($dlon / 180) * cos($lat2 / 180);
    	my $x = cos($lat1 / 180) * sin($lat2 / 180) - sin($lat1 / 180) * cos($lat2 / 180) * cos($dlon / 180);
	my $angle = atan2( $y, $x ) * 57.2957795;
	return $angle;
}
# 
# arccos(rad)
sub acos(@) {
    	my $rad = shift;
    	my $arccos = atan2(sqrt(1 - $rad**2),$rad);
    	return $arccos;
}
# 
# decimal degrees to radians
sub deg2rad(@){
    	my $deg = shift;
    	my $rad = $deg * $pi / 180;
	return $rad;
}
# 
# Radians to decimal degrees
sub rad2deg(@){
    	my $rad = shift;
	my $deg = $rad * 180 / $pi;
	return $deg;
}
#
# Calculate distance between two coordinates.
sub distance(@) {
    	my ($lat1,$lon1,$lat2,$lon2) = @_;
    	my $theta = $lon1 - $lon2;
    	my $dist = rad2deg(acos(sin(deg2rad($lat1)) * sin(deg2rad($lat2)) + cos(deg2rad($lat1)) * cos(deg2rad($lat2)) * cos(deg2rad($theta))));
	my $distance;
	# calculate the distance using the required unit:
	if ($defaultdistanceunit =~ /^mile$/) {
  		$distance = int($dist * 69.09 * 100) / 100;        # mile
	} elsif ($defaultdistanceunit =~ /^meter$/) {
   		$distance = int($dist * 111189.57696);             # meter
	} elsif ($defaultdistanceunit =~ /^nauticalmile$/) {
    		$distance = int($dist * 59.997756 * 100) / 100;    # nautical mile
	} else {
   		$distance = int($dist * 111.18957696 * 100) / 100; # kilometer
	}
    	return $distance;
}
#
#===============================================================================
# Handle the process using a pid (process id) file.
sub Check_pid(@){
	my $pidfile = shift;
	my $pid;
	# return if pidfile does not exists..
	return 0 if (! -e $pidfile);
	my @cat =`cat $pidfile`;
	foreach my $line (@cat) {
        	chomp($line);
		# get pid from pidfile...
		$pid =$1 if ($line =~ /^(\d+)$/);
	}
	if (!$pid) {
		# pidfile without pid
		unlink($pidfile);
		return 0;
	}
	# check if process still exists.
	my @process =`ps -ef | grep $pid | grep -v grep`;
	my $result;
	foreach my $line (@process) {
		chomp($line);
		# pi        2773  2160 29 22:04 pts/0    00:00:09 /usr/bin/perl -w ./client-0.2.pl
		$result =$1 if ($result = $line =~ /^\w+\s+($pid)\s+\d+/);
	}
	# return if pid pidfile is a running process
	return $pid if ($result);
	# remove pidfile if process is no longer running...
	unlink($pidfile);
	return 0;
}
# Compose pid file
my $hostalias = $PEER_HOST;
$hostalias =~ s/\./_/g if ($hostalias =~ /^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$/);
LOG("The data directory/file is: $datadirectory/".filedate($hostalias).".txt","I");
LOG("The log  directory/file is: $logdirectory/".filedate($hostalias).".log","I");
my $pidfile = "$piddirectory/dump1090-$hostalias.pid";
# 
if (-e $pidfile) {
	# pid file already exists
	my $pid = Check_pid($pidfile);
	if ($status) {
		if ($pid) {
			LOG("'$scriptname' ($pid) is running!","I");
		} else {
			LOG("'$scriptname' is not running!","I");	
		}
		exit;
	} elsif ($restart) {
		if ($pid) {
                        LOG("'$scriptname' ($pid) is running!","I");
			unlink($pidfile);
			if (-e $pidfile) {
				LOG("Unable to remove '$pidfile' ($pid)! '$scriptname' is not restarting....","E");
				exit 1;
			}
			LOG("Stopping '$scriptname' ($pid)....","I");
			sleep 2;
		} else { 
			LOG("'$scriptname' is not running!","W");
		}
		LOG("Starting '$scriptname'....","I"); 
	} elsif ($stop) {
		if ($pid) {
                        LOG("'$scriptname' ($pid) is running!"."I");
                } else {
                        LOG("'$scriptname' is not running!","W");
			exit 1;
                }
                unlink($pidfile);
		if (-e $pidfile) {
			LOG("Unable to remove '$pidfile' ($pid)! '$scriptname' is not stopping.....","E");
                        exit 1;
		}
		LOG("Stopping '$scriptname' ($pid)....","I");
		sleep 2;
		exit 0;
	} else {
		if ($pid) {
			LOG("Unable to start '$scriptname'. '$scriptname' ($pid) is already running!","W");
			exit 1;
                } else {
                        LOG("'$scriptname' will be started!","I");
                }
	}
} else {
	# There is no pid file
	if ($status) {
		LOG("'$scriptname' is not running!","I");
		exit 0;
	} elsif ($restart) {
		LOG("'$scriptname' was not running, but it is starting now!","W");
	} elsif ($stop) {
		LOG("'$scriptname' was not running....","W");
		exit 1;
	} else {
		LOG("Starting '$scriptname'....","I");
	}
}
# Create pid file with pid number inside.
my $pid =$$;
my @cmd =`echo $pid > $pidfile`;
if (! -e $pidfile) {
	LOG("Unable to create '$pidfile'! '$scriptname' ($pid) is not starting....","W");
	exit 1;
} else {
	LOG("'$scriptname' ($pid) is started! Using pidfile $pidfile.","I");
}
#
#===============================================================================
# Main program
my $previous_date ="";
my $previous_minute = 0;
my $previous_second = 0;
my $data_filehandle;
my $message_count = 0;
my $position_count = 0;
my $flight_count = 0;
my %flight;
# Data Header
my @header = ("message_type","transmission_type","session_id","aircraft_id","hex_ident","flight_id","generated_date","generated_time","logged_date","logged_time","callsign","altitude","ground_speed","track","lat","lon","vertical_rate","squawk","alert","emergency","spi","is_on_ground");
my %hdr;
my $columnnumber = 0;
# Save colum name with colomn number in hash.
foreach my $header (@header) {
	$hdr{$header} = $columnnumber;
	$columnnumber++;
}
#
#===============================================================================
# Socket that reads data from the PEER_HOST over port 30003.
$proto = getprotobyname('tcp');    #get the tcp protocol
$connectioncount=0;
my ($SOCKET);
while (1) {
	# create a socket handle (descriptor)
	socket($SOCKET, AF_INET, SOCK_STREAM, $proto) or die "could not create socket : $!";
	# connect to remote server
	$iaddr = inet_aton($PEER_HOST) or die "Unable to resolve hostname : $PEER_HOST";
	$paddr = sockaddr_in("30003", $iaddr);    #socket address structure    
	connect($SOCKET , $paddr) or die "connect failed : $!";
	LOG("Connected to $PEER_HOST on port 30003","D");
	$connectioncount++;
	#
	# Read messages from the 30003 socket in a continuous loop:
	my $errorcount = 0;
	while ($message = <$SOCKET>){
		$message_count++;
	  	chomp($message);
		if ($debug) {
			if ($message) {
				LOG("messagecount=$message_count,message='$message'","D");	
			} else {
				LOG("messagecount=$message_count,message=''","W");
			}
		}
		# Split line into colomns:
		my @col = split /,/,$message;
		my $hex_ident = $col[$hdr{'hex_ident'}];
		# Check whether if has enough columns and a hex_ident:
		if ((@col > 20) && ($hex_ident) && ($hex_ident =~ /^[0-9A-F]+$/i)){
			$errorcount = 0;
		} else {
			$errorcount++;
			if (($errorcount == 100) || ($errorcount == 1000)) {
				# write an error message to the log file after 100 or 1000 incomplete messages in a row:
				LOG("messagecount=$message_count, incomplete messages in a row: $errorcount, last message='$message'","L");
			} elsif ($errorcount > 10000) {
				# Exits the script after 10000 incomplete messages in a row:
				LOG("messagecount=$message_count, incomplete messages in a row: $errorcount, last message='$message'. Exit script......","E");
				LOG("Not able to read proper data from the socket! Check whether your dump1090 is running on '$PEER_HOST' port 30003 (tcp).","E");
				exit;
			}
			next;
		}
		$epochtime = time;
		# Flight first time seen:
		if (! exists $flight{$hex_ident}{'lastseen'}) {
			# Save time in epoch when the flight was first seen.
			$flight{$hex_ident}{'firstseen'} = $epochtime; 
			# Overall flight count (per day):
			$flight_count++;
			# Position count per flight:
			$flight{$hex_ident}{'position_count'} = 0;
			$flight{$hex_ident}{'message_count'} = 0;
		}
		# Save time when flight was last seen:
		$flight{$hex_ident}{'lastseen'} = $epochtime; 
		# Count messages per flight:
		$flight{$hex_ident}{'message_count'}++;
		# Compose filedate
  		my ($second,$day,$month,$year,$minute) = (localtime)[0,3,4,5,1];
		my $filedate = 'dump1090-'.$hostalias.'-'.sprintf '%02d%02d%02d', $year-100,($month+1),$day;
		# Every second we want to check whether the pid file is still there.
		if($previous_second ne $second) {
			$previous_second = $second;
			if (!-e $pidfile) {
				# The PID file was removed (by an outside process).
				# This means it is time to exit.....
				$interrupted = "The '$scriptname' ($pid) was interrupted. The pidfile $pidfile was removed by an outside process...!";		
			}
		}
		# Handle data and log file:
  		if($filedate ne $previous_date){
			# Close files if they were open:
			if ($previous_date ne "") {
				close $data_filehandle;
			}
			# Set newfile date:
  			$previous_date=$filedate;
			# Open files 
    			open($data_filehandle, '>>',"$datadirectory/$filedate.txt") or die "Unable to open '$datadirectory/$filedate.txt'!\n";
    			$logfile = common->LOGset($logdirectory,"$filedate.log",$verbose);
    			$data_filehandle->autoflush;
			# write header: 
		        print $data_filehandle "hex_ident,altitude($defaultaltitudeunit),latitude,longitude,date,time,angle,distance($defaultdistanceunit),squawk,ground_speed($defaultspeedunit),track,callsign\n";
			# reset counters for a new day:
			$message_count = 1;
			$position_count = keys %{$flight{$hex_ident}};
			$flight_count = keys %flight;
  		}
		# Check every minute for hex_ident's that can be retiered:
		if (($minute ne $previous_minute) || ($interrupted)) {
			if (-e $pidfile) {
                                my @cmd=`cat $pidfile`;
                                $pidfilestatus="";
                                for $line (@cmd) {
                                        chomp($line);
                                        if ($line =~ /^$pid$/){
                                                $pidfilestatus="ok";
                                        }
                                }
                                if ($pidfilestatus !~ /ok/) {
                                        # The PID file was changed (by an outside process).
                                        # This means it is time to exit.....
                                        $interrupted = "The '$scriptname' ($pid) was interrupted. The pid with the pidfile $pidfile was changed by an outside process...!";
                                }
                        }
			$previous_minute = $minute;
			# Log overall statistics:
			LOG("current number of flights=".scalar(keys %flight).",epoch=".epoch2date($epochtime).",msg_count=$message_count,pos_count=$position_count,flight_count=$flight_count,con_lost=$connectioncount.","L"); 
			foreach my $hex_ident (keys %flight) {
				# check if flight was not seen for longer than 120 secondes:
				next unless ((($flight{$hex_ident}{'lastseen'} + 120) < $epochtime) || ($interrupted));
				# Set position_count zero if there are no positions for this flight.
				$flight{$hex_ident}{'position_count'} = 0 if (! exists $flight{$hex_ident}{'position_count'});
				# Log flight statistics:
				LOG("removed:$hex_ident,first seen=".epoch2date($flight{$hex_ident}{'firstseen'}).",last seen=".epoch2date($flight{$hex_ident}{'lastseen'}).",message_count=$flight{$hex_ident}{'message_count'},position_count=$flight{$hex_ident}{'position_count'}.","L"); 
				# remove flight information (and prevent unnessesary memory usage).
				delete $flight{$hex_ident};
			}
			if ($interrupted) {
				LOG("Exit: $interrupted","I");			
				exit;
			}
		}
		# Get logged date & time:
		# 2015/04/06,19:14:29.596
		my $loggeddatetime = $col[$hdr{'logged_date'}].",".$col[$hdr{'logged_time'}];
		my ($hour,$millisecond);
		if (($year,$month,$day,$hour,$minute,$second,$millisecond) = $loggeddatetime =~ /^(\d{4})\/(\d{2})\/(\d{2}),(\d{2}):(\d{2}):(\d{2})\.(\d{1,3})$/){
			# change date & time into epoch time in milliseconds:
       		        $loggeddatetime = (timelocal($second,$minute,$hour,$day,($month-1),$year).$millisecond) * 1000;
		} else {
			# No valid date & time format
			 next;
		}
       	 	# Save callsign
       	 	if ($col[$hdr{'callsign'}] =~ /[a-z0-9]+/i) {
       	 		$flight{$hex_ident}{'callsign'} = $col[$hdr{'callsign'}];
		}
		# Save longitude and datetime
		if ($col[$hdr{'lon'}] =~ /\./) {
			$flight{$hex_ident}{'lon'} = $col[$hdr{'lon'}];
			$flight{$hex_ident}{'lon_loggedtime'} = $loggeddatetime;
		}
		# Save latitude and datetime
		if ($col[$hdr{'lat'}] =~ /\./) {
			$flight{$hex_ident}{'lat'} = $col[$hdr{'lat'}];
			$flight{$hex_ident}{'lat_loggedtime'} = $loggeddatetime;
		}
		# Save Altitude and datetime
		if ($col[$hdr{'altitude'}] =~ /^\d*[123456789]\d*\.?\d*$/) {
			my $altitude = $col[$hdr{'altitude'}];
			if ($defaultaltitudeunit =~ /^meter$/) {
				# save feet as meters:
				$flight{$hex_ident}{'altitude'} = int($altitude / 3.2828);
			} else {
				# save as feet:
				$flight{$hex_ident}{'altitude'} = int($altitude);
			}
			$flight{$hex_ident}{'altitude_loggedtime'} = $loggeddatetime;
		}
		# Save squawk
		if ($col[$hdr{'squawk'}] =~ /^\d+$/) {
			$flight{$hex_ident}{'squawk'} = $col[$hdr{'squawk'}];
		}
		# Save track
		if ($col[$hdr{'track'}] =~ /^\d+\.?\d*$/) {
			$flight{$hex_ident}{'track'} = $col[$hdr{'track'}];
		}
		# Save speed
		if ($col[$hdr{'ground_speed'}] =~ /^\d*[123456789]\d*\.?\d*$/) {
			my $speed = $col[$hdr{'ground_speed'}];
			if ($defaultspeedunit =~ /^mileph$/) {
				# save knots as miles:
				$flight{$hex_ident}{'ground_speed'} = int($speed * 1.150779);
			} elsif ($defaultspeedunit =~ /^kilometerph$/) {
				# save knots as kilometers
				$flight{$hex_ident}{'ground_speed'} = int($speed * 1.852);
			} else {
				# save as knots as knots
				$flight{$hex_ident}{'ground_speed'} = int($speed);
			}
		}
		# Be sure that the requiered fields (longitude, latitude and altitude) for this flight are captured:
		next unless ((exists $flight{$hex_ident}{'lon'}) && (exists $flight{$hex_ident}{'lat'}) && (exists $flight{$hex_ident}{'altitude'})); 
		# If there is a time difference, calculate the time differences between messages:
		my $diff1 = abs($flight{$hex_ident}{'lon_loggedtime'} - $flight{$hex_ident}{'lat_loggedtime'});
		my $diff2 = abs($flight{$hex_ident}{'lon_loggedtime'} - $flight{$hex_ident}{'altitude_loggedtime'});
		my $diff3 = abs($flight{$hex_ident}{'lat_loggedtime'} - $flight{$hex_ident}{'altitude_loggedtime'});
		# Be sure that the time differance between the messages is less than $TIME_MESSAGE_MARGIN.
		next unless (($diff1 < $TIME_MESSAGE_MARGIN) && ($diff2 < $TIME_MESSAGE_MARGIN) && ($diff3 < $TIME_MESSAGE_MARGIN));
       	 	# Skip this one. All the values need to be different...
       	 	next if ((exists $flight{$hex_ident}{'prev_lon'})      		  && ($flight{$hex_ident}{'lon'}      		 eq $flight{$hex_ident}{'prev_lon'}) &&  
       	          (exists $flight{$hex_ident}{'Prev_lat'})      		  && ($flight{$hex_ident}{'lat'}      		 eq $flight{$hex_ident}{'Prev_lat'}) &&  
       	          (exists $flight{$hex_ident}{'prev_altitude'}) 		  && ($flight{$hex_ident}{'altitude'} 		 eq $flight{$hex_ident}{'prev_altitude'}));
		# Skip this one. All the values need to be from a new moment...
		next if ((exists $flight{$hex_ident}{'prev_lon_loggedtime'})      && ($flight{$hex_ident}{'lon_loggedtime'}      eq $flight{$hex_ident}{'prev_lon_loggedtime'}) && 
			 (exists $flight{$hex_ident}{'Prev_lat_loggedtime'})      && ($flight{$hex_ident}{'lat_loggedtime'}      eq $flight{$hex_ident}{'Prev_lat_loggedtime'}) && 
			 (exists $flight{$hex_ident}{'prev_altitude_loggedtime'}) && ($flight{$hex_ident}{'altitude_loggedtime'} eq $flight{$hex_ident}{'prev_altitude_loggedtime'}));
		
		# Count the positions per flight and overall:
		$flight{$hex_ident}{'position_count'}++;
		$position_count++;
		# Get angle and distance
		my $angle = int(angle($latitude,$longitude,$flight{$hex_ident}{'lat'},$flight{$hex_ident}{'lon'}) * 100) / 100;
		my $distance = distance($latitude,$longitude,$flight{$hex_ident}{'lat'},$flight{$hex_ident}{'lon'});	
		# Write the data to the data file:
		print $data_filehandle "$hex_ident,$flight{$hex_ident}{'altitude'},$flight{$hex_ident}{'lat'},$flight{$hex_ident}{'lon'},$col[$hdr{'logged_date'}],$col[$hdr{'logged_time'}],$angle,$distance,".($flight{$hex_ident}{'squawk'}||"").",".($flight{$hex_ident}{'ground_speed'}||"").",".($flight{$hex_ident}{'track'}||"").",".($flight{$hex_ident}{'callsign'}||"")."\n";
		# Save the values per flight to examine the next position.
		$flight{$hex_ident}{'prev_lon'}      		= $flight{$hex_ident}{'lon'};
		$flight{$hex_ident}{'Prev_lat'}      		= $flight{$hex_ident}{'lat'};
		$flight{$hex_ident}{'prev_altitude'}            = $flight{$hex_ident}{'altitude'};
       	 	$flight{$hex_ident}{'prev_lon_loggedtime'}      = $flight{$hex_ident}{'lon_loggedtime'};
       		$flight{$hex_ident}{'Prev_lat_loggedtime'}      = $flight{$hex_ident}{'lat_loggedtime'};
       	 	$flight{$hex_ident}{'prev_altitude_loggedtime'} = $flight{$hex_ident}{'altitude_loggedtime'};
		# Display statistics when running interactive:
		if (($interactive) && (!$nopositions)) {
			my $back = length "positions:".$position_count;
                	print "positions:".$position_count, substr "\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b", 0, $back;
		}
	}
	LOG("lost TCP connection","D");
}

# This cleanup routine will be executed even when the script is stopped by an 'exit' of CTRL-C.
END {
	# Clean up pidfile (if exists)
	if (($pidfile) && (-e $pidfile)) {
		my @cat =`cat $pidfile`;
		foreach my $line (@cat) {
			chomp($line);
			# clean only when it matches the PID
			my $pid =$$;
			unlink($pidfile) if ($line =~ /^$pid$/);
		}
	}
}	
1;
