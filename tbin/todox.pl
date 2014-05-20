#!/usr/bin/perl -w
#*********************************************************************
#
# todox.pl
# Modified todo.pl see  
# http://unattended.svn.sourceforge.net/viewvc/unattended/trunk/install/bin/todo.pl 
# for original todo.pl
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

use warnings;
use strict;
use Getopt::Long;
use Pod::Usage;
use File::Spec::Functions  qw(catfile splitpath); #_new_
use File::Path qw(make_path);#_new_
use Config::General; #_new_

#####################
### Configuration ###
#####################

# Logfile Nr. 1 => Until get logfile configuration from configfile 
my $log;
if(-w '/var/log/' ){
	$log = '/var/log/tuvalu.log';
}else{
	print("Error: Can't create logfile '/var/log/tuvalu.log'! Abort.");
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
}elsif(-r $path."tuvalu.conf"){
	$configFile = $path."tuvalu.conf";
}

if($configFile ne ""){
	my $conf = new Config::General(
		-ConfigFile      => $configFile,
		-InterPolateVars => 1,
	);
	%config = $conf->getall;
}else{

	print("Can't read config-file, using defaults. (Config-file have to be '/etc/tuvalu/tuvalu.conf' or in the same folder as tuvalu.pl.) $!\n");
}


# Next config-file
my $configFileNew = &setConfigOrDefault('next_config_linux',$configFile,'f','r');

if($configFileNew ne $configFile){
	$conf = new Config::General(
		-ConfigFile      => $configFileNew,
		-InterPolateVars => 1,
	);
	%config = $conf->getall;
}
$configFile = $configFileNew;

# Logfile Nr. 2
$log = &setConfigOrDefault('log_file',$log,'f','w');
$logSize = &setConfigOrDefault('log_size','500000','i',"");
if(-e $log and -s "$log" > $logSize){
	rename($log,"$log.old");
}

# Path to tuvalu (server-side)
my $z = &setConfigOrDefault('path_to_tuvalu_linux','/opt/tuvalu','p','r');
 # script path
my $path_to_scripts = &setConfigOrDefault('path_to_scripts', catfile($z,'scripts'),'p','r');
 # bin (tuvalu.pl, todo*.pl)
my $path_to_bin = &setConfigOrDefault('path_to_bin', catfile($z,'tbin'),'p','r');

# Pathe to client-side tuvalu
my $x = &setConfigOrDefault('path_to_local_tuvalu', '/var/lib/tuvalu','p','w');
(-w catfile($x,"scripts") or make_path(catfile($x,"scripts")) > 0) or &writeLogfile($log,"Can't create directory ". catfile($x,'scripts')." ($!)!",1,"E") and exit 5;
my $local_scripts_dir = catfile($x,'scripts');

my $todo = catfile($x,'todo.txt');				# holds the commands for todo.pl

my $errorhandle = &setConfigOrDefault('error_handle', "abort",'','');
my $errorretries = &setConfigOrDefault('error_retries', "1",'i','');



# Your usual option-processing sludge.
my %opts;
GetOptions (\%opts, 'help', 'user', 'go')
    or pod2usage (2);

(exists $opts{'help'})
    and pod2usage ('-exitstatus' => 0, -verbose => 2);

sub stop () {
    while (1) {
        sleep 3600;
    }
}

# Since this is the top-level "driver" script, stop if we encounter
# any problems.
END {
    $? == 0
        and return;

    print "E: $0 exiting with status $?;\n";
	exit $?;
}

##########################
### setConfigOrDefault ###
##########################
# Checks, if 1. parameter exists in config file, if not set to default (2. parameter). 
# If file or path, tests condition, specified by 4. parameter (r, w) and deletes
# leading %z and %x and replaces them with $x and $z variable. 3. parameter specifies
# the typ (i:integer, f:file, p: path)
# 1. Parameter: config file entry
# 2. Parameter: default value
# 3. Parameter: typ (i:integer, f:file, p: path)
# 4. Parameter: if path or file, test condition
sub setConfigOrDefault{
	my $ret =(exists $config{$_[0]} and length($config{$_[0]})!= 0 )?$config{$_[0]}:$_[1];
	if($_[2] eq 'f'){
		chop($ret) if($ret =~ /(\\|\/)$/);
		if($_[3] eq 'r'){
			-r $ret or &writeLogfile($log,"File $ret (config-file entry '$_[0]') not readeable!",1,"E") and exit 4;
		}
		if($_[3] eq 'w'){
			my ($volume, $path) = splitpath($ret);
			(-w $ret  or (!-e $ret and -w $path)) or &writeLogfile($log,"File $ret (config-file entry '$_[0]') not writeable!",1,"E") and exit 5;
		}
		return $ret;
	}
	if($_[2] eq 'p'){
		if($_[3] eq 'r'){
			-r $ret or &writeLogfile($log,"Directory $ret (config-file entry '$_[0]') not readeable!",1,"E") and exit 4;
		}
		if($_[3] eq 'w'){
			(-w $ret or make_path($ret) > 0) or &writeLogfile($log,"Directory $ret (config-file entry '$_[0]') not writeable!",1,"E") and exit 5;
		}
		return $ret if($ret !~ /(\\|\/)$/);
		chop($ret);
		return $ret;
	}
	if($_[2] eq 'i'){ # is integer
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


##################
### linux_dist ###
##################
# Finds the distributionname (debian, ubuntu, ...), the releasename of the distribution
# and the codename form /etc/lsb-release. Returns array in his order.
sub linux_dist{
	my $lsbr = '/etc/lsb-release';
	my $dist = "";
	my $release = "";
	my $codename = "";
	if(-r $lsbr){
		my @lsb = &read_file($lsbr);
		foreach(@lsb){
			if($_ =~ m/^DISTRIB_ID=(.*)$/){
				$dist = $1;
				next;
			}
			if($_ =~ m/^DISTRIB_RELEASE=(.*)$/){
				$release = $1;
				next;
			}
			if($_ =~ m/^DISTRIB_CODENAME=(.*)$/){
				$codename = $1;
			}
		}
	}else{
		print "File $lsbr not readeable!";
	}
	return ($dist, $release, $codename);
}



sub reboot () {
    print "$0 is bouncing the system\n";
    system "shutdown -r now" or &writeLogfile($log,"Unable to shutdown system: $^E",1,"E") and exit 6;
	stop();
}


# Read a file.  Return an empty list if file does not exist.
sub read_file ($) {
    my ($file) = @_;

    -e $file
        or return ();

    open FILE, $file
        or &writeLogfile($log,"Unable to open $file for reading: $^E",1,"E") and exit 4;
    my @ret = <FILE>;
    close FILE
        or &writeLogfile($log,"Unable to close $file: $^E",1,"E") and exit 6;
    map { chomp } @ret;

    # Cull empty lines
    return grep { /./ } @ret;
}

# Write some lines to a file.
sub write_file ($@) {
    my ($file, @lines) = @_;

    if (scalar @lines > 0) {
        my $tmp = "$file.tmp.$$";
        open TMP, ">$tmp"
            or &writeLogfile($log,"Unable to open $tmp for writing: $^E",1,"E") and exit 5;
        foreach my $line (@lines) {
            print TMP "$line\n";
        }
        close TMP
            or &writeLogfile($log,"Unable to close $tmp: $^E",1,"E") and exit 6;

        rename $tmp, $file
            or &writeLogfile($log,"Unable to rename $tmp to $file: $^E",1,"E") and exit 5;
    }
    else {
        # When file becomes empty, remove it.
        unlink $file
            or &writeLogfile($log,"Unable to unlink $file: $^E",1,"E") and exit 5;
    }
}


# Push one or more commands onto the to-do list.
sub push_todo (@) {
    my @new_cmds = @_;

    my @old_cmds = read_file ($todo);
    write_file ($todo, @new_cmds, @old_cmds);
}

# Pop the next command off of the to-do list.  With arg, just peek at
# the next command; do not really pop it off.
sub pop_todo (;$) {
    my ($peek) = @_;
    my @cmds = read_file ($todo);

    scalar @cmds > 0
        or return undef;

    my $ret = shift @cmds;

    $peek
        or write_file ($todo, @cmds);

    return $ret;
}

sub peek_todo () {
    return pop_todo (1);
}


# Run a command, including handling of pseudo-commands (like .reboot).
# If second arg is true, return exit status ($?) instead of bombing if
# non-zero.
$ENV{'_TODO_RETRY'} = $errorretries;
my $ugly ="";
sub do_cmd ($;$);
sub do_cmd ($;$) {
    my ($cmd, $no_bomb) = @_;
    my $ret;

    if ($cmd =~ /^\./) {
        if ($cmd eq '.reboot') {
print "jjjjj\n";
            &reboot();
            die 'Internal error';
        }
        elsif ($cmd =~ /^\.expect-reboot\s+(.*)$/) {
            my $new_cmd = $1;
            do_cmd ($new_cmd);
			&writeLogfile($log,"Expecting previous command to reboot; exiting.",1,"!") and exit 0;

        }
        elsif ($cmd =~ /^\.reboot-on\s+(\d+)\s+(.*)$/) {
            my ($err_to_reboot, $new_cmd) = ($1, $2);
            my $status = do_cmd ($new_cmd, 1);

            if ($status == $err_to_reboot << 8) {

				&writeLogfile($log,"$new_cmd exited status $err_to_reboot; rebooting.",1,"!");
                do_cmd ('.reboot');
                die 'Internal error';
            }

            $ret = $status;
        }
        elsif ($cmd =~ /^\.missing-ok\s+(.*)$/) {
            my $new_cmd = $1;
            my $status = do_cmd ($new_cmd, 1);

            $status == 1 << 8
                and $status = 0;

            $ret = $status;
        }
        elsif ($cmd =~ /^\.ignore-err\s+(\d+)\s+(.*)$/) {
            my ($err_to_ignore, $new_cmd) = ($1, $2);
            my $status = do_cmd ($new_cmd, 1);
			my $real_status = ($status>>8);
            ($real_status == $err_to_ignore or $real_status == 0)
                and $status = 0;

            $ret = $status;
        }
        elsif ($cmd =~ /^\.ignore-all-err\s+(.*)$/) {
            my $new_cmd = $1;
            my $status = do_cmd ($new_cmd, 1);
            my $real_status = $status << 8;

            if ($real_status == 0) {
                $ret = 0;
            } elsif ($real_status == 1) {
                $ret = 1;
            } else {
                $ret = 0;
            }
        }
        elsif ($cmd =~ /^\.sleep\s+(\d+)$/) {
            my ($secs) = $1;
            print "Sleeping $secs seconds...";
            sleep $secs;
            print "done.\n";
            $ret = 0;
        }
        else {
			&writeLogfile($log,"Unrecognized pseudo-command $cmd",1,"E") and exit 6;
        }
    }
    else {
	## log actions
	&writeLogfile($log,"Start running: $cmd",0,"-");
	print "Start running: $cmd\n";

        my $status = system $cmd;
	&writeLogfile($log,"Stop running: $cmd, status $status",0,"-");
	$ret = $status;
    }

    defined $ret
        or &writeLogfile($log,"Internal error. Unexpected exit code ($ret) from $cmd",1,"E") and exit 6;

    unless ($no_bomb) {
        while ($ret != 0) {
			my $dret = $ret >> 8;

            #print "$cmd failed, status $dret (", $ret % 256, ')', "\n";

            if ($errorhandle =~ m/^abort$/i) {
				push_todo($cmd);	# save command
				&writeLogfile($log,"$cmd failed with status $dret. Aborting.",1,"E");
				exit 6;
            }
            elsif ($errorhandle =~ m/^retry.*$/i) {
				if($ENV{'_TODO_RETRY'} != 0){
					$ENV{'_TODO_RETRY'} = $ENV{'_TODO_RETRY'} - 1;
					#print "\n";
					&writeLogfile($log,"$cmd failed with status $dret. Retrying (".($ENV{'_TODO_RETRY'}+1)." times).",1,"!");
					return do_cmd ($cmd);
				}elsif($errorhandle =~ m/^retry&skip$/i){
					$ugly = "skip";
					$ENV{'_TODO_RETRY'} = $errorretries;
				}elsif($errorhandle =~ m/^retry(&abort)*$/i){
					$ENV{'_TODO_RETRY'} = $errorretries;
					push_todo($cmd);	# save command
					&writeLogfile($log,"$cmd failed with status $dret. Aborting.",1,"E");
					exit 6;
            	}elsif($errorhandle =~ m/^retry&ignore$/i){
					$ugly = "ignore";
					$ENV{'_TODO_RETRY'} = $errorretries;
            	}
			}
			if($errorhandle =~ m/^ignore$/i or $ugly eq "ignore") {
				$ugly =  "";
                &writeLogfile($log,"$cmd failed with status $dret. Ignoring.",1,"W");
                $ret = 0;
            }elsif ($errorhandle =~ m/^skip$/i or $ugly eq "skip") {
				$ugly =  "";
				&writeLogfile($log,"$cmd failed with status $dret. Skipping $cmd.",1,"W");
				my $nextTodo;
				do{		# Skipping all cmds till tuvalu.pl --addversion  or  tuvalu.pl --delversion  occurs
					$nextTodo = pop_todo();
					if(defined $nextTodo ){ 
						&writeLogfile($log,"Skipping $nextTodo, too",1,"W"); 
					}else{
						last;	# end of file
					}
				}while($nextTodo !~ m/^.*tuvalu.pl\s+--addversion.+$/i and $nextTodo !~ m/^.*tuvalu.pl\s+--delversion.+$/i);
                $ret = 0;
            }else{
				&writeLogfile($log,"Unrecognized entry '$errorhandle' for 'error_handle' in $configFile.",1,"E");
				push_todo($cmd);	# save command
				exit 6;
			}
        }
    }
return $ret;
}

exists $opts{'user'} || $> == 0  # are we root?
    or &writeLogfile($log,"Not root and --user not supplied",1,"E") and exit 6;

if (exists $opts{'go'}) {
    @ARGV == 0
        or pod2usage (2);
	
    # Prevent re-entrancy.
    (exists $ENV{'_IN_TODO'})
        and exit 0;
    $ENV{'_IN_TODO'} = 'yes';

    # Add "tbin" and "scripts" directories to PATH.	
    $ENV{'PATH'} = "$path_to_bin:$path_to_scripts:$local_scripts_dir:$ENV{'PATH'}";
	my @dist = &linux_dist();

    # Set the distribution name (e. g. debian, ubuntu)
    $ENV{'DISTRIBUTION'} = shift(@dist);

    # Set the release of current distribution
    $ENV{'DISTRELEASE'} = shift(@dist);

    # Set the codename of current distribution
    $ENV{'CODENAME'} = shift(@dist);

	$ENV{'Z'} = $z;
#system "printenv";
    while (defined (my $cmd = pop_todo ())) {
        do_cmd ($cmd);
    }
}
else {
    # Default behavior is to push one or more commands onto the todo list.
    @ARGV > 0
        or pod2usage (2);
    push_todo (@ARGV);
}

exit 0;

__END__

=head1 NAME

todox.pl - Manage the to-do list

=head1 SYNOPSIS

todo.pl [ options ] <commands...>

=head1 OPTIONS

--help          Display help and exit
--go            Process the to-do list
--user          Run in "per user" mode

=head1 DESCRIPTION

todo.pl manages the "to do" list, a plain-text file.

Normally, it simply prepends its arguments to the list.

If invoked with --go, it removes commands from the list one at a time
and executes them in a controlled environment. 


=head1 SEE ALSO
L<http://unattended.sourceforge.net/apps.html#todo>
