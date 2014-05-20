#!/usr/bin/perl -w
#*********************************************************************
#
# tuvalu.pl - Version v1.0
#
# This script is part of the tuvalu project
# Copyright (C) 2011/12 Martin Schulte
#
#*********************************************************************
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful, but
# WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
# General Public License for more details.
#
# A copy of the GNU General Public License is available as
# '/usr/share/common-licences/GPL' in the Debian GNU/Linux distribution
# or on the World Wide Web at http://www.gnu.org/copyleft/gpl.html.  You
# can also obtain it by writing to the Free Software Foundation, Inc.,
# 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301, USA
#*********************************************************************
use Time::HiRes;
my $one = [Time::HiRes::gettimeofday];
use strict;
use warnings;
use Config::General;
use Cwd;
use Getopt::Long;
use Pod::Usage;
use Sys::Hostname;
use File::Spec::Functions  qw(catfile splitpath);
use File::Path qw(make_path mkpath);
use version;




###############
### Options ###
###############
my %opts;
my $verboseOpt =0;
my $fileOpt;
my @addversion;
my $delversion;
my $removeOpt;

GetOptions(\%opts, 'verbose' => \$verboseOpt,'help', 'sync' , 'remove', 'dry','installonly', 'updateonly', 'addversion=s{2}' => \@addversion, 'delversion=s' => \$delversion, 'file=s'  => \$fileOpt)  or pod2usage (1);

if(exists $opts{'help'}){
	pod2usage ('-exitstatus' => 0, -verbose => 2);
}

if($verboseOpt == 1){
	print "\nMarker: (-) Information, (W) Warning, (E) Error, (!) notice\n".
		    "-----------------------------------------------------------\n";
}

# If any problem encounter, exit 
END{
	$? == 0
		and return;
	
	print "$0 exiting with status $?\n";
	exit $?;
}

#####################
### Configuration ###
#####################

# Logfile Nr. 1 => Until get logfile configuration from configfile 
my $log;
if(-w '/var/log/' ){
	$log = '/var/log/tuvalu.log';
}elsif($^O ne "linux" and (-w "$ENV{'Programfiles'}/tuvalu/" or make_path("$ENV{'Programfiles'}\\tuvalu\\")) > 0){
	$log = "$ENV{'Programfiles'}/tuvalu/tuvalu.log";
}else{
	$log = ($^O eq "linux")?'/var/log/tuvalu.log':"\%Programfiles%\\tuvalu\\tuvalu.log";
	print("Error: Can't create logfile $log! Abort.");
	exit 15;
}
my $logSize = 500000;		# Cleaning up
if(-e $log and -s "$log" > $logSize){
	rename($log,"$log.old");
}

### Read the config file ###
############################
my $configFile = "";
my $conf;
my %config;
my ($volume, $path) = splitpath($0);

if(-r '/etc/tuvalu/tuvalu.conf'){
	$configFile = '/etc/tuvalu/tuvalu.conf';
}elsif($^O ne "linux" and -r "$ENV{'Programfiles'}\\tuvalu\\tuvalu.conf"){
	$configFile = "$ENV{'Programfiles'}\\tuvalu\\tuvalu.conf";
}elsif(-r $volume.$path."tuvalu.conf"){
	$configFile = "$volume$path"."tuvalu.conf";
	# if a special conf-file for windows exists.
	if($^O ne "linux" and -r "$volume$path"."tuvalu.win.conf"){
		$configFile = "$volume$path"."tuvalu.win.conf";
	}
}

if($configFile ne ""){
	my $conf = new Config::General(
		-ConfigFile      => $configFile,
		-InterPolateVars => 1,
	);
	%config = $conf->getall;
}else{
	my $tmp = ($^O eq "linux")?'/etc/tuvalu/tuvalu.conf':"$ENV{'Programfiles'}\\tuvalu\\tuvalu.conf";
	print("Can't read config-file, using defaults. (Config-file must be $tmp or in the same folder as tuvalu.pl.) $!\n");
}


# Next config-file
# the old way
#my $configFileNew = ($^O eq "linux")?&setConfigOrDefault('next_config_linux',$configFile,'f','r'):&setConfigOrDefault('next_config_win',$configFile,'f','r');

#if($configFileNew ne $configFile){
#	$conf = new Config::General(
#		-ConfigFile      => $configFileNew,
#		-InterPolateVars => 1,
#	);
#	%config = $conf->getall;
#}

# Logfile Nr. 2
$log = &setConfigOrDefault('log_file',$log,'f','w');
$logSize = &setConfigOrDefault('log_size','500000','i',"");
if(-e $log and -s "$log" > $logSize){
	rename($log,"$log.old");
}

#########################
### Run early command ###
#########################
my $earlyCommand = &setConfigOrDefault('early_command','','','');
my $earlyCommandExitStatus = &setConfigOrDefault('early_command_exit_status','0','i','');

my $status;
if($earlyCommand ne ""){
	&writeLogfile($log,"Run early cmd: $earlyCommand");
	$status = system $earlyCommand; 
	$status == $earlyCommandExitStatus << 8 or &writeLogfile($log,"Early command '$earlyCommand' exited with status ".($status >> 8)." (expected $earlyCommandExitStatus to go on)!",1,"!") and exit 0;
}


# Path to tuvalu (server-side)
my $z = ($^O eq "linux")?&setConfigOrDefault('path_to_tuvalu_linux','/opt/tuvalu','p','r'):&setConfigOrDefault('path_to_tuvalu_win',"\\\\install\\tuvalu",'p','r');
 # script path
my $path_to_scripts = &setConfigOrDefault('path_to_scripts', catfile($z,'scripts'),'p','r');
 # conf (hosts.linux, hosts.win, disabled, groups)
my $path_to_conf = &setConfigOrDefault('path_to_conf', catfile($z,'conf'),'p','r');
 # bin (tuvalu.pl, todo*.pl)
my $path_to_bin = &setConfigOrDefault('path_to_bin', catfile($z,'tbin'),'p','r');

# Path to client-side tuvalu ( default  /var/lib/tuvalu for linux and %PROGRAMFILES%\tuvalu\ for windows
my $x = ($^O eq "linux")?&setConfigOrDefault('path_to_local_tuvalu', '/var/lib/tuvalu','p','w'):&setConfigOrDefault('path_to_local_tuvalu',"$ENV{PROGRAMFILES}\\tuvalu",'p','w');
(-w catfile($x,"scripts") or mkpath(catfile($x,"scripts"),0,) > 0) or &writeLogfile($log,"Can't create directory ". catfile($x,'scripts')." ($!)!",1,"E") and exit 5;
my $local_scripts_dir = catfile($x,'scripts');

# Hostname
my $hostname = &Hostname();
$hostname = &setConfigOrDefault('hostname',$hostname,"","");

# paths
my $installedFile = catfile($x,"$hostname.installed");	# Info about installed and versionnumbers
if(&setConfigOrDefault('hostname_in_filename',0,'i') == 0){
	$installedFile = catfile($x,"this.installed");	# No hostname in filename if set so in tuvalu.conf
}
my $todo = catfile($x,'todo.txt');						# holds the commands for todo*.pl
my $disabledFile = ($^O eq "linux")?catfile($path_to_conf,'disabled.linux'):catfile($path_to_conf,'disabled.win');
my $hostfile = ($^O eq "linux")?catfile($path_to_conf,'hosts.linux'):catfile($path_to_conf,'hosts.win');
my $groupfile = ($^O eq "linux")?catfile($path_to_conf,'groups.linux'):catfile($path_to_conf,'groups.win');

# middle and late command
my $middleCommand = &setConfigOrDefault('middle_command','','','');
my $middleCommandExitStatus = &setConfigOrDefault('middle_command_exit_status','0','i','');

my $lateCommand = &setConfigOrDefault('late_command','','','');
my $lateCommandExitStatus = &setConfigOrDefault('late_command_exit_status','0','i','');

# Up to here we have:
#	$hostname: 		The hostname
#	$log			Logfile
#	$path_to_scripts	The server-side script directory
#	$path_to_bin		Where tuvalu.pl / todo*.pl and helperscripts are.
#	$path_to_conf		Where the hosts/groups/disabled-files are
#	  $hostfile 		scripts/cmds applied to host and groups
#	  $groupfile		groups definition
#	  $disabledFile		Host or group disabled?
#	$local_scripts_dir	Where the remove- and updatescripts are stored.
#	$installedFile		File with information about installed and versionnumbers
#	$todo			holds the cmds for todo*.pl

if($verboseOpt == 1 or exists $opts{'dry'}){
	print "\nConfiguration\n";
	print "-------------\n";
	print "Hostname:         $hostname\n";
	print "Logfile:          $log\n";
	print "Server-side script-directory:\n";
	print "                  $path_to_scripts\n";
	print " Hostfiles:       $hostfile\n"	;
	print " Groupfiles:      $groupfile\n"	;
	print " Host/groups disabled:\n";
	print "                  $disabledFile\n"	;
	print "Client-side script-directory:\n";
	print "                  $local_scripts_dir\n";
	print "Installed/Version $installedFile\n";
	print "The todo.txt:     $todo\n-------------\n\n";
}


##########################
### Handle the options ###
##########################
if(@addversion > 0){
		my %versionfile = &getVersionOfInstalled($installedFile);
		$versionfile{$addversion[0]} = $addversion[1];
		&writeLogfile($log,"Adding $addversion[0]|$addversion[1] to $installedFile",$verboseOpt,'-');
		&writeHashToFile($installedFile,\%versionfile);
		exit 0;
}
if(defined $delversion){
		my %versionfile = &getVersionOfInstalled($installedFile);
		delete $versionfile{$delversion}; 
		&writeLogfile($log,"Deleting $delversion in $installedFile",$verboseOpt,'-');
		&writeHashToFile($installedFile,\%versionfile);
		exit 0;
}
$opts{'sync'} = 1 if (exists $opts{'updateonly'} and !defined $fileOpt and @ARGV == 0); # --sync as default
$opts{'sync'} = 1 if (exists $opts{'installonly'} and !defined $fileOpt and @ARGV == 0);
pod2usage ('-exitstatus' => 0, -verbose => 2) if (!exists $opts{'sync'} and !defined $fileOpt and @ARGV == 0);	# Nothing to do in this case
pod2usage ('-exitstatus' => 0, -verbose => 2) if (exists $opts{'sync'} and  exists $opts{'remove'});	# What will you do?







#################
### Main Task ###
#################
my @groups;
# Host disabled (only makes sense if you use --sync)?
if(exists $opts{'sync'}){
	# find eyerything the host belongs to: hostname, groups, ALL
	@groups = &findGroupsAndHost($groupfile);
	# Check if host or group of host is disabled
	if(-r $disabledFile ){
		for my $tmp (@groups){
			if(grep { $_ eq $tmp } &fileToArray($disabledFile )){	# hostname or my group in the disabled.xxx
				&writeLogfile($log,"Host disabled in $disabledFile (entry $tmp).",1,"!");
print Time::HiRes::tv_interval ($one, [Time::HiRes::gettimeofday]);
				exit 0;
			}
		}
	}
}

# oLd place
##########################
### Run middle command ###
##########################
#if($middleCommand ne "" ){
#	&writeLogfile($log,"Run middle cmd: $middleCommand");
#	$status = system $middleCommand; 
#	$status == $middleCommandExitStatus << 8 or   &writeLogfile($log,"Middle command '$middleCommand' exited with status ".($status >> 8)." (expected $middleCommandExitStatus to go on)!",1,"!") and exit 0;
#}

##################################
### Run old cmds from todo.txt ###
##################################
$status = 0;
&setPATH($path_to_bin);	# For todo*.pl
if(-e $todo and !exists $opts{'dry'}){
	if($^O eq "linux"){
		$status = system "todox.pl --go";
	}else{
		$status = system "todo.pl --go";
	}
	$status == 0 << 8 or   &writeLogfile($log,"Executing old commands from $todo exited with status ".($status >> 8)." Aborting!",1,"!") and exit 6;
}

my @thisHostCmd=(); # will contain all commands --> from hosts.xxx, @ARGV or --file=... -option;


# Three ways to get the commands
# 1. If file is specified with file=..., this are the cmd/scripts
if(defined $fileOpt){
	push(@thisHostCmd,&fileToArray($fileOpt));
	$removeOpt = 0;
	&writeLogfile($log,"Scripts and commands from file $_[1]:  ".join(",",&fileToArray($fileOpt)),$verboseOpt,'-');
}

# 2. If arguments are given, this are the cmd/scripts
if(@ARGV > 0){
	push(@thisHostCmd,@ARGV);
	$removeOpt = 0;
	&writeLogfile($log,"Scripts and commands directly called:  ".join(",",@ARGV),$verboseOpt,'-');
}
# 3. If hosts.xxx should be used.
if(exists $opts{'sync'}){
	-r $hostfile or &writeLogfile($log,"Hostfile $hostfile doesn't exist or isn't readable.",1,"!") and exit 4;
	# find cmd/scripts applied to this host
	push(@thisHostCmd,&findCmdForHost($hostfile, \@groups));
	&writeLogfile($log,"Scripts and commands defined for this host in $hostfile:  ".join(",",&findCmdForHost($hostfile, \@groups)),$verboseOpt,'-');
	$removeOpt = 1;
}


print "-: Looking for installed in $installedFile.\n" if $verboseOpt == 1;
my %installed = &getVersionOfInstalled($installedFile);
if(($verboseOpt == 1 or exists $opts{'dry'}) and keys %installed){
	print "Installed:\n----------\n";
	foreach (sort {uc($a) cmp uc($b)} keys(%installed)){
		print "  $_  (version $installed{$_})\n";
	}
	print "----------\n\n";
}




if (exists $opts{'remove'}){
	@thisHostCmd = reverse &buildRemoveCmd(\@thisHostCmd,$local_scripts_dir,\%installed);  # Only if no --sync, look above
}else{
	# change cmd, if there is sth. to update or remove.
	@thisHostCmd = &findScriptsForHost($path_to_scripts, \@thisHostCmd, \%installed, $local_scripts_dir);
}

if(@thisHostCmd == 0){
	&writeLogfile($log,"No cmds. Nothing todo for this host.",$verboseOpt,'!');
}else{
	##########################
	### Run middle command ###
	##########################
	if($middleCommand ne "" ){
		&writeLogfile($log,"Run middle cmd: $middleCommand");
		$status = system $middleCommand; 
		$status == $middleCommandExitStatus << 8 or   &writeLogfile($log,"Middle command '$middleCommand' exited with status ".($status >> 8)." (expected $middleCommandExitStatus to go on)!",1,"!") and exit 0;
	}




	# Write everything to the todo.txt
	&writeLogfile($log,"Writing ".(scalar @thisHostCmd)." commands to $todo.",$verboseOpt,'-');
	print "Cmds for todo-list:\n-------------------\n".join("\n",@thisHostCmd)."\n-------------------\n\n" if ($verboseOpt == 1 or exists $opts{'dry'});
	arrayToFile($todo, @thisHostCmd);
	# and call the todo*.pl
	&writeLogfile($log,"Calling the 'todo*.pl driver' script.",$verboseOpt,'-') unless(exists $opts{'dry'});
	unless(exists $opts{'dry'}){
		if($^O eq "linux"){
			system "todox.pl --go";
		}else{
			system "todo.pl --go";
		}
	}
}


########################
### Run late command ###
########################
if($lateCommand ne ""){
	&writeLogfile($log,"Run late cmd: $lateCommand");
	$status = system $lateCommand; 
	$status == $lateCommandExitStatus << 8 or   &writeLogfile($log,"Late command '$lateCommand' exited with status ".($status >> 8)." (expected $lateCommandExitStatus to go on)!",1,"!") and exit 0;
}

print "Lasted ".(Time::HiRes::tv_interval ($one, [Time::HiRes::gettimeofday]))." seconds.\n" if $verboseOpt == 1;;


exit 0;



##########################
### setConfigOrDefault ###
##########################
# Checks, if 1. parameter exists in config file, if not set to default (2. parameter). 
# If file or path, tests condition, specified by 4. parameter (r, w). 3. parameter 
# specifies the typ (i:integer, f:file, p: path)
# 1. Parameter: config file entry
# 2. Parameter: default value
# 3. Parameter: typ (i:integer, f:file, p: path)
# 4. Parameter: if path or file, test-condition
sub setConfigOrDefault{
	my $ret =(exists $config{$_[0]} and length($config{$_[0]})!= 0 )?$config{$_[0]}:$_[1]; # Default or in config-file?
	if($_[2] eq 'f'){	# handle files
		chop($ret) if($ret =~ /(\\|\/)$/);
		if($_[3] eq 'r'){
			-r $ret or &writeLogfile($log,"File $ret (config-file entry '$_[0]') not readable!",1,"E") and exit 4;
		}
		if($_[3] eq 'w'){
			my ($volume, $path) = splitpath($ret);
			(-w $ret  or (!-e $ret and -w $volume.$path)) or &writeLogfile($log,"File $ret (config-file entry '$_[0]') not writeable!",1,"E") and exit 5;
		}
		return $ret;
	}
	if($_[2] eq 'p'){ # handle paths
		if($_[3] eq 'r'){
			-r $ret or &writeLogfile($log,"Directory $ret (config-file entry '$_[0]') not readable!",1,"E") and exit 4;
		}
		if($_[3] eq 'w'){
			(-w $ret or make_path($ret) > 0) or &writeLogfile($log,"Directory $ret (config-file entry '$_[0]') not writeable!",1,"E") and exit 5;
		}
		return $ret if($ret !~ /(\\|\/)$/);
		chop($ret);
		return $ret;
	}
	if($_[2] eq 'i'){ # test integer
		$ret =~ /^[+-]?\d+$/ or &writeLogfile($log,"config-file entry '$_[0]' isn't numeric ($ret).",1,"E") and exit 13;
	}
	return $ret;
}

####################
### WriteLogFile ###
####################
# Appends a line (specified by 2. Parameter) + current time to the end of the
# Logfile (specified by the 1. Parameter). 4. Parmeter is W = Warning, E = Error
# ! = notice. If 3. parameter is 1, it also wil be display to STDOUT

sub writeLogfile{
	my $file = $_[0];
	my $line = $_[1];
	my $lineV = $line; # For verbose output
	my $verbose = (defined $_[2])?$_[2]:0;
	my $type = (defined $_[3])?$_[3]:"-";
	my $typeV = (defined $_[3])?"$_[3]: ":"";
	my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
	$year += 1900;
	$mon += 1;
	$mon = ($mon < 10)?"0$mon":$mon;
	$mday = ($mday < 10)?"0$mday":$mday;
	$hour = ($hour < 10)?"0$hour":$hour;
	$min = ($min < 10)?"0$min":$min;
	$sec = ($sec < 10)?"0$sec":$sec;
	my $time = "$year-$mon-$mday $hour:$min:$sec";
	if(-s $file){
		$line = "$time ($type) $line";
	}else{
		$line = "# Marker: (-) Information, (W) Warning, (E) Error, (!) notice\n\n$time ($type) $line";
	}
	open FILE, '>>' , "$file" or die "Can't open Logfile $file: $!\n";
	print FILE "$line\n";
	close FILE;
	if($verbose == 1){
		print ("$typeV$lineV\n");
	}
}

###################################
### fileToArray ###################
###################################
# Returns array with file contents
# 1. Parameter: file
sub fileToArray{
	open FILE, $_[0]  or &writeLogfile($log,"Can't open file $_[0] ($!)",1,"E") and exit 4;
	my @bar;
	while(my $line = <FILE>){
		next if $line =~ m/^#/; # skip comment-lines
		$line =~ s/\s*#.*$//; 	# delete comments
		next if $line =~ m/^\s*$/; # skip empty lines 
#		unless($line =~ m/^\s*#/ or $line =~ m/^\s*$/){	# only lines without '#', and no empty lines
			push(@bar, $line);
#		}
	}
	close FILE;
	chomp(@bar);	# Delete all \n
	return @bar;
}

###################################
### arrayToFile ###################
###################################
# Write arraycontent to file. Each entry is one line.
# 1. Parameter: file
sub arrayToFile{
    my ($file, @lines) = @_;
    if (scalar @lines > 0) {
        open(FILE, '>', $file) or &writeLogfile($log,"File $_[0] not writeable ($!).",1,"E") and exit 4;
        foreach(@lines) {
            print FILE "$_\n";
        }
        close FILE;
	}
}

###################################
### findHostname ##################
###################################
# Returns hostname
sub Hostname{
	my @hostname = split(/\./,hostname());
	return $hostname[0];
}

###################################
### delWhitespace #################
###################################
# Deletes leading and trailing whitspace
sub delWhitespace{
	$_[0] =~ s/\s+$//g; # begin
	$_[0] =~ s/^\s+//g; # end
	return $_[0];
}

###################################
### filesInDirToArray #############
###################################
# Writes all files of an directory into an array
# Parameter: path
# return: array with all files in path.
sub filesInDirToArray{
	my @bar;
	opendir ( DIR, $_[0] ) or &writeLogfile($log,"Can't enter directory $_[0] ($!)",1,"E") and exit 3;
		while(my $file = readdir(DIR)){
			next unless(-f catfile($_[0],$file));		# file? or directory?
			push(@bar, $file)
		}
		closedir(DIR);
	return @bar;
}


###################################
### getVersionFromScripts #########
###################################
# Extract version number from file (parameter), format:   :: Version|1.11.2
# Parameter: Script-file
sub getVersionFromScripts{
	my $line;
	my $versionnumber;
	my $tmp = "\|0";
	open(FILE, '<', $_[0])  or &writeLogfile($log,"File $_[0] doesn't exists or not readable ($!).",1,"E") and exit 4;
	while($line = <FILE>){
		if($line =~ m/\.*Version.*\|.*/i){
			$tmp = $line;
			chomp($tmp);
			last;	# only one version-string is allowed
		}
	}
	close(FILE);
	($line, $versionnumber) = split(/\|/,$tmp);
	$versionnumber = &delWhitespace($versionnumber);
	if($verboseOpt == 1){
		print "    - Found version string ($tmp).\n" if $tmp ne "\|0";
		print "    - No version string, set version to 0.\n" if $tmp eq "\|0";
	}
	return $versionnumber;
}

###################################
### getVersionOfInstalled #########
###################################
# Returns an hash with the installed software refers to the versionnumber (e.g. firefox.bat => 5.0.1)
# Parameter: file with information about installed software ($installedFile)
sub getVersionOfInstalled{
	my %installedVersion;
	unless(-r $_[0]){
		&writeLogfile($log,"File $_[0] doesn't exists or not readable ($!). No information about versionnumbers. Doesn' matter if you execute for the first time.",$verboseOpt,"!");
		return %installedVersion;
	}
	open(FILE, '<', $_[0])  or return %installedVersion;
		while(my $line = <FILE>){
			unless($line =~ m/^(\s*|\s*#+.*)$/){	# No empty lines, no comments
				my ($key, $value) = split(/\|/,$line);
				chomp($value);
				$installedVersion{$key} = $value;  
			}
		}
	close(FILE);
	return %installedVersion;
}

###################################
### writeHashToFile ###############
###################################
# Writes an hash (2. Parameter) to file (1. Parameter)
sub writeHashToFile{
	my %hash = %{$_[1]};	# deref. 
	open(FILE, '>', $_[0])  or &writeLogfile($log,"Can't create file $_[0] or not writeable ($!).",1,"E") and exit 4;
		print FILE "#\n";
		print FILE "# DO NOT EDIT THIS FILE\n";
		print FILE "#\n";
		print FILE "## It is automatically generated\n";
		print FILE "## Use\n";
		print FILE "##     tuvalu.pl --addversion <scriptname> <versionnumber>\n";
		print FILE "##     tuvalu.pl --delversion <scriptname>\n";
		print FILE "## instead.\n";
		print FILE "#\n";
		foreach (sort {uc($a) cmp uc($b)} keys(%hash)){
			print FILE "$_\|$hash{$_}\n";
		}
	close(FILE);
}

###################################
### generateUpdateScript ##########
###################################
# generates a file (2. Parameter) from a special formated file (1. Parameter)
#	:: Update | commands1
#	:: UPDATE | commands2
# becomes
#
# @Echo off
# commands 1
# commands 2
#
# returns 0 if such structure exist, if no structure exists, returns -1, if R&I returns 1.
# 3. Parameter: String for information:
sub generateUpdateScript{
	my $commentSign = ($^O eq "linux")?'#':'::';	# Comments: linux "#", win "::"
	my $line;
	my $command;
	my @commands;
	my @output=();
	my $tmp;
	my $ret = -1;
	# Read from File $_[0]
	open(FILE, '<', $_[0])  or &writeLogfile($log,"File $_[0] doesn't exists or not readable ($!).",$verboseOpt) and return -1;
	while($line = <FILE>){
		if($line =~ m/.*Update.*\|.*/i){
			($tmp, @commands) = split(/\|/,$line);
			$command = join('|',@commands); # if pipe-symbol is used
			#($tmp, $command) = split(/\|/,$line);
			if($command =~ m/\s*R&I\s*$/){
				$ret = 1;
				last;
			}
			push(@output, &delWhitespace($command));
			$ret = 0;
		}
	}
	close(FILE);
	if($ret == 0){
		splice(@output,1,0,"\n$commentSign $_[2]\n");	# because of the Shebang line on linux systems ...
		print "    - Found update information in $_[0], write them to $_[1].\n" if $verboseOpt == 1;
		# Write to file $_[1]
		open(FILE, '>', $_[1])  or &writeLogfile($log,"Can't create file $_[0] or not writeable ($!).",$verboseOpt,"W") and return -1;
		foreach(@output){		
			print FILE "$_\n";
		}
		close(FILE);
		chmod(0744, $_[1]);
	}
	return $ret;
}


###################################
### generateRemoveScript ##########
###################################
# generates a file (2. Parameter) from a special formated file (1. Parameter)
#	:: REMOVE | commands1
#	:: ReMoVe | commands2
# becomes
#
# commands 1
# commands 2
#
# returns 0 if such structure exist, else -1.
# 3. Parameter: String for information
sub  generateRemoveScript{
	my $commentSign = ($^O eq "linux")?'#':'::';	# Comments: linux "#", win "::"		
	my $line;
	my $command;
	my @commands;
	my @output=();
	my $tmp;
	my $res = 0;
	# Read from File $_[0]
	open(FILE, '<', $_[0])  or &writeLogfile($log,"File $_[0] doesn't exist or not readable ($!).",$verboseOpt) and return;
	while($line = <FILE>){
		if($line =~ m/.*Remove.*\|.*/i){
			#($tmp, $command) = split(/\|/,$line);
			($tmp, @commands) = split(/\|/,$line);
			$command = join('|',@commands); # if pipe-symbol is used
			push(@output, &delWhitespace($command)); # Maybe, there is a whitespace in front of the cmd, doesn't matter in general, but for shebang
			$res = 1;
		}
	}
	close(FILE);
	unless($res == 0){
		splice(@output,1,0,"\n$commentSign $_[2]\n");	# because of the shebang line on linux systems ...
		print "    - Found remove information in $_[0], write them to $_[1].\n" if $verboseOpt == 1;
		# Write to file $_[1]
		open(FILE, '>', $_[1])  or &writeLogfile($log,"Can't create file $_[0] or not writeable ($!).",$verboseOpt,"W") and return;
		foreach(@output){		
			print FILE "$_\n";
		}
		close(FILE);
		chmod(0744, $_[1]);
	}else{
		&writeLogfile($log,"No remove information for new version in $_[0].",$verboseOpt,"!");
	}
}

##########################
### uniqueArray ##########
##########################
# Returns the unique array of he given array
sub uniqueArray{
	my %foo;
	@_ = grep !$foo{$_}++, @_;
	return @_;
}

##########################
### setPATH ##############
##########################
# Sets PATH enviroment variable (prepend to existing entrys), no matter if linux (:) or win (;).
# Parameter: Variable value
sub setPATH{
	if($^O eq "linux"){
		$ENV{'PATH'} = "$_[0]:$ENV{'PATH'}";
	}else{
	    $ENV{'PATH'} = "$_[0];$ENV{'PATH'}";
	}
}

##########################
### findGroupsAndHost ####
##########################
# Finds all all groups belong to this host
# Parameter: File with groups definition ($groupfile)
# returns array with hostname, all groups and group ALL
sub findGroupsAndHost{
	my @groups=($hostname); # will contain all groups for this host
	my $group;	# temporary group (foreach loop)
	# Find groups for this host
	if(-r $_[0]){
		my @allGroups = &fileToArray($_[0]); # each line sth. like:  @groupname;host00;host01;host02
		my @hostsOfGroup; 
		foreach(@allGroups){
			($group, @hostsOfGroup) = split(/;/, $_);
			$group = &delWhitespace($group);
				foreach(@hostsOfGroup){
					$_ = &delWhitespace($_);
					if($_ eq $hostname){
						push(@groups, $group);
											}
				}
		}
		&writeLogfile($log,"Groups of this host ($hostname) are: ".join((", ",@groups[1..$#groups])),$verboseOpt,"-");
	}else{
		&writeLogfile($log,"No groups defined for this host ($hostname) in $_[0]. ",$verboseOpt,"-");
	}
	push(@groups, "ALL");
	return @groups
}

######################
### findCmdForHost ###
######################
# Finds all all cmds belong to this host
# 1. Parameter: host.define-file
# 2. Parameter: Arrayreferenz to group-array
# returns unified array with all scripts for this host.
sub findCmdForHost{
	my @groups = @{$_[1]};		# deref. array
	my $firstEntry;
	my @hostAndCmd = &fileToArray($_[0]); # each line sth. like:  <hostname>;firefox;thunderbird;putty
	my @hostsCmd=();			# Cmds of current line
	my @thisHostCmd=(); 	# Will contain all scripts for this host (hostname, groups, All)
	foreach(@hostAndCmd){
		($firstEntry ,@hostsCmd) = split(/;/, $_);
		$firstEntry = &delWhitespace($firstEntry);
		# Check scripts applied to host and groups or ALL
		foreach(@groups){
			if($_ eq $firstEntry){
				push(@thisHostCmd, @hostsCmd);
			next;
			}
		}		
	}
	# Delete leading and trailing whitespace
	return @thisHostCmd;
}

##########################
### findScriptsForHost ###
##########################
# Find out, which commands are (*.bat|*sh)-files in the script directory.
# This are the scripts, (could) containing the Version, Remove, Update, ... information 
# 1. Parameter: Path to the scripts directory (where the *.bat or *.sh files are, $path_to_scripts)
# 2. Parameter: Arrayreferenz to the array which contains the commands for this host.
# 3. Paremeter: Hash reference to hash which installed scripts and version
# 4. Parameter: Path to the local scripts directory
# returns modified and unified array with all commands for this host (maybe foo.bat becomes foo-update.bat).
sub findScriptsForHost{
	my @filesInScriptDir = &filesInDirToArray($_[0]);
	my @thisHostCmd =grep{ $_ !~ m/^\s*$/; } @{$_[1]};	# Delete empty lines
	foreach(@thisHostCmd){$_ = &delWhitespace($_);}	# delete Whitespaces (a little bit time-intensiv ... )
	@thisHostCmd = &uniqueArray(@thisHostCmd); 			# unify the array
	my @notRemove=(); 	# collecting scripts, which stay on system, later the complement $_[2]\@notRemove delivers remove-commands.
	my $i;
	OUTER:
	for($i=0; $i<@thisHostCmd; $i++){ # loop over all commands ..
		foreach(@filesInScriptDir){	# ... if script exists install, update or remove.
			if(-T catfile($_[0],$_)){		# this scripts have to be textfiles --> have to read version/remove/update info
				if($_ eq $thisHostCmd[$i] or $_ =~ m/^$thisHostCmd[$i]\.bat$/i){ # "bat.-files are cmds"
					print "-: $_  found in $_[0]\n" if $verboseOpt == 1;
					# for scripts called with .bat extension. 
					# or for scripts called without .bat extension (win)
					my @depends = &findDepends($_,$_[0]);	# Finds dependencies
					foreach my $foo (@notRemove){		# Cmd/script from dependencies run before? If -> remove
						@depends = grep { $foo ne $_} @depends;
					}
					if(@depends > 0){	# in case, add @depends and run again.
						&writeLogfile($log,"$_ depends on ".join(", ",@depends).". Will run them first, if necessary.",$verboseOpt,"-");
						splice(@thisHostCmd,$i,0,@depends);	# add at current index and redo loop.
						@thisHostCmd = (@thisHostCmd[0..$i-1],&uniqueArray(@thisHostCmd[$i..$#thisHostCmd])); 	# Maybe dependencies still exists
						redo OUTER;						
					}
				$thisHostCmd[$i] = &InstallOrUpdate($_ ,$_[0], $_[2], $_[3]);	# What's to do?
				push(@notRemove, $_);	# Of course, don't remove it.
				next OUTER;
				}
			}
		}
	# because of 'next' above, only reach this, if cmd is no script
		push(@notRemove, $thisHostCmd[$i]);	
		if(exists $opts{'updateonly'}){
			$thisHostCmd[$i] = "";
			next;
		}
		if(exists $_[2]->{$thisHostCmd[$i]}){ # run before, then ...
			&writeLogfile($log,"$thisHostCmd[$i]: Nothing to do.",$verboseOpt,"-");
			$thisHostCmd[$i] = "";			# ... nothing to do.
		}else{ # if new cmd
			&writeLogfile($log,"$thisHostCmd[$i]: Will be run.",0,"-");
			print "-: $thisHostCmd[$i]: Isn't a script in $_[0], will be treated as a command.\n" if $verboseOpt == 1;
			$thisHostCmd[$i] = "$thisHostCmd[$i]\n$0 --addversion $thisHostCmd[$i] 0";	# Run this cmd
		}
		
	}
	if(!exists $opts{'updateonly'} and !exists $opts{'installonly'}){
		foreach(@notRemove){	# calc th complement of %installed and @notRemove
			delete $_[2]->{$_};	 # Delete from %installed
		}
		if($removeOpt == 1){	
			my @remove = keys %{$_[2]};
			unshift(@thisHostCmd,&buildRemoveCmd(\@remove,$_[3],$_[2]));	# build remove cmds (find remove-scripts in $local_scripts and add them.
		}
	}
	# unify again, because maybe there was a cmd named foo and one named foo.bat --> both are now foo.bat
	@thisHostCmd = &uniqueArray(@thisHostCmd);
	@thisHostCmd=grep{ $_ !~ m/^\s*$/; } @thisHostCmd; # Remove empty entries
	return @thisHostCmd;
}


###################################
### buildRemoveCmd ################
###################################
# 1. Parameter: Arrayreference with cmd/scripts should be removed
# 2. Parameter: Path to the local scripts directory
# 3. Paremeter: Hash reference to hash which installed scripts and version
# returns Array with remove cmd (finds the removescripts).
sub buildRemoveCmd{
	my @removeCmd=();
	for(@{$_[0]}){		# Build remove cmd for $_[0]
		exists $_[2]->{$_} or &writeLogfile($log,"$_ should be removed, but isn't mentioned as installed on this system. Nothing to do for me.",$verboseOpt,"!") and next;
		my ($extension, $name) = &chopFilename($_);
		if(-r catfile($_[1],"$name-remove$extension")){			# is there an remove script?
			unshift(@removeCmd,"$name-remove$extension\n$0 --delversion $_");	# Cmd to remove from <hostname>.installed
			&writeLogfile($log,"$_: Will be removed.",$verboseOpt,"-");
		}else{
			&writeLogfile($log,"Can't find remove-script ".catfile($_[1],"$name-remove$extension")." ($!). Nothing to do for me.",$verboseOpt,"W");
		}
	}
	return @removeCmd;
}
###################################
### InstallOrUpdate ###############
###################################
# compares Versionnumbers an decides if update or new installation
# If install, remove-script will be generate
# 1. Parameter: Scriptsfile
# 2. Parameter: Path to the scripts dir ($path_to_scripts)
# 3. Parameter: Hash-reference to the hash of the installed software and coresponding versionnumbers
# 4. Parameter: Directory for local scripts ($local_scripts_dir).
sub InstallOrUpdate{
	my $out = "";
	my %installedVersions = %{$_[2]};	# deref.
	my $versionInstalled;
	my $versionScript = &getVersionFromScripts(catfile($_[1],$_[0]));
	$versionScript =~ m/^s*v*(\d*\.*)*$/  or (&writeLogfile($log,"Versionnumber in $_[0] incorrect.",1,"W") and return "");
	$versionScript = version->parse($versionScript);
	my ($extension, $name) = &chopFilename($_[0]);
# script never run before, so run this script and generate remove-script
	if(!exists $_[2]->{$_[0]}){				
			$out = "    - Installation possible, but '--updateonly' selected.\n" if $verboseOpt == 1;
			!exists $opts{'updateonly'} or print $out and return "";		# but only if not updateonly is selected
			generateRemoveScript(catfile($_[1],$_[0]),catfile($local_scripts_dir,"$name-remove$extension"), "Remove $name (Version: $versionScript)", $_[3]);
			&writeLogfile($log,"$_[0]: New script, will be run (version: $versionScript)",$verboseOpt,"-");
			return "$_[0]\n$0 --addversion $_[0] $versionScript";
	}
# if ran before, versionnumber exists
	$versionInstalled = $_[2]->{$_[0]};
	chomp($versionInstalled);
	$versionInstalled = version->parse($versionInstalled);	# convert for comparison
# no revision
	if($versionScript == $versionInstalled){
		$out = "    - Newest version, no installation necessary.\n" if $verboseOpt == 1; # for verbose output
		!exists $opts{'installonly'} or print $out and return ""; 	# but only if not installonly is selected
		&writeLogfile($log,"$_[0] is the newest version ($versionScript).",$verboseOpt,"-");
		return "";
	}
# newer version
	if($versionScript > $versionInstalled ){
		$out = "    - Update possible, but '--installonly' selected.\n" if $verboseOpt == 1;
		!exists $opts{'installonly'} or print $out and return "";
		# generate update script, 0: success, -1: no update information, 1: remove first and install new
		my $foo = &generateUpdateScript(catfile($_[1],$_[0]),catfile($local_scripts_dir,"$name-update$extension"), "Update $name$extension (Version: $versionScript)", $_[3]);
		generateRemoveScript(catfile($_[1],$_[0]),catfile($local_scripts_dir,"$name-remove$extension"), "Remove $name (Version: $versionScript)", $_[3]);
	# Everything is fine, updatescripts was generated.
		if($foo == 0){
			&writeLogfile($log,"$_[0]: Will be updated to $versionScript",$verboseOpt,"-");
			return "$name-update$extension\n$0 --addversion $_[0] $versionScript";
		}
	# First remove, than install new Version
		if($foo == 1){	
			# is there an remove script?
			if(-r catfile($_[3],"$name-remove$extension")){	
					&writeLogfile($log,"$_[0]: Will remove old version ($versionInstalled) and install version $versionScript.",$verboseOpt,"-");
					rename(catfile($_[3],"$name-remove$extension"),catfile($_[3],"$name-remove-old$extension"));	# Next line generates remove-script for new version
					generateRemoveScript(catfile($_[1],$_[0]),catfile($local_scripts_dir,"$name-remove$extension"), "Remove $name (Version: $versionScript)", $_[3]);
					return "$name-remove-old$extension\n$_[0]\n$0 --addversion $_[0] $versionScript";	# return remove-script and install script
			# no remove script generated, when script was installed or updated
			}else{
					&writeLogfile($log,"$_[0]: Should be removed and install new for update, but no remove information. Nothing to do for me. Stay on version $versionInstalled.",$verboseOpt,"-");
					return "";						# nothing todo
			}
		}
	# No update information => nothing todo
		if($foo == -1){	
			&writeLogfile($log,"$_[0]: There is a newer version ($versionScript), but no update information. Nohing to do.",$verboseOpt,"-");
			return "";
		}

	}
# installed version is newer than script version. evtl. downgrade ergänzen.
	&writeLogfile($log,"$_[0]: Installed version ($versionInstalled) newer than script version ($versionScript).",$verboseOpt,"-");
	return "";  # if $versionScript < $versionInstall, sth. went wrong ...
}

###################################
### chopFilename ##################
###################################
# Devides filename into name an extension: 

# eg.: foo.bar     --> foo    and .bar
#      foo.bar.dat --> foo.bar   and .dat
# 1. Parameter: filename
# Returns @array (extension, name)

sub chopFilename{
	my @file = split(/\./,$_[0]); # split at dot
	return (".".pop(@file), join(".",@file)) if @file >1;
	return ("", @file);
}


###################################
### findDepends ###################
###################################
# finds dependecies in a special formated file 
#	:: DEPENDS | script;cmd1;cmd2
#
# 1. Parameter: File
# 2. Parameter: Path to script directory
# returns an array with all necessary cmds/scripts
sub  findDepends{
	my $line;
	my @command=();
	my $tmp;
	# Read from File $_[0]
	open(FILE, '<', catfile($_[1],$_[0]))  or &writeLogfile($log,"File $_[1]/$_[0] doesn't exist or not readable ($!).",$verboseOpt) and return @command;
		while($line = <FILE>){
			if($line =~ m/\.*Depends.*\|.*/i){
				($tmp, @command) = split(/\|/,$line);	# $line = :: DEpends | foo.bat;bar.bat;...
				@command = split(/;/,$command[0]);		# all scripts
				last;									# only one Depends statement is allowed
			}
		}
	close(FILE);
	chomp(@command);
	@command =grep{ $_ !~ m/^\s*$/; } @command;	# Delete empty lines
	foreach(@command){$_ = &delWhitespace($_);}
	return  @command;
}
	


__END__

=head1 NAME

tuvalu.pl - Prepare the to-do list for todo*.pl

=head1 SYNOPSIS

tuvalu.pl [ options ] <commands...>

=head1 OPTIONS

--help          Display help and exit
--dry           Only check files. Don't run any script
--sync          Check files for scripts should be run, generate the todo-list and run the todo.pl driver script. 
--file=...      Take this file for getting information about scripts shall be run on this client.
--remove        Only run remove-scripts, do not run install- or update-scripts
--installonly	Only install, do not run update- or remove-scripts. 
--updateonly	Only update, do not run install- or remove-scripts.

=head1 DESCRIPTION

tuvalu.pl generates the todo-list for the todo.pl script. 
