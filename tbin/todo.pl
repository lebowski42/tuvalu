#!/usr/bin/perl -w
#*********************************************************************
#
# todo.pl
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
my %reg;
use Win32API::Registry qw(:Func :SE_);
use Win32::TieRegistry (Delimiter => '/', TiedHash => \%reg);
#use Win32::NetResource; # for get_drive_path
use File::Spec::Functions  qw(catfile splitpath); #_new_
use File::Path qw(make_path);#_new_
use Config::General; #_new_


# New vonfiguration of $z, $todo, $log
# Delete run_at_logon
# Add setConfigOrDefault()


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
my $configFileNew = ($^O eq "linux")?&setConfigOrDefault('next_config_linux',$configFile,'f','r'):&setConfigOrDefault('next_config_win',$configFile,'f','r');

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
my $z = ($^O eq "linux")?&setConfigOrDefault('path_to_tuvalu_linux','/mnt/tuvalu','p','r'):&setConfigOrDefault('path_to_tuvalu_win',"\\\\install\\tuvalu",'p','r');
 # script path
my $path_to_scripts = &setConfigOrDefault('path_to_scripts', catfile($z,'scripts'),'p','r');
 # bin (tuvalu.pl, todo.pl)
my $path_to_bin = &setConfigOrDefault('path_to_bin', catfile($z,'tbin'),'p','r');

# Pathe to client-side tuvalu
my $x = ($^O eq "linux")?&setConfigOrDefault('path_to_local_tuvalu', '/var/lib/tuvalu','p','w'):&setConfigOrDefault('path_to_local_tuvalu',"$ENV{PROGRAMFILES}\\tuvalu",'p','w');
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

    print "$0 exiting with status $?;\n";
    #stop ();
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
			(-w $ret  or (!-e $ret and -w $volume.$path)) or &writeLogfile($log,"File $ret (config-file entry '$_[0]') not writeable!",1,"E") and exit 5;
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
	if($_[2] eq 'i'){
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



sub reboot ($) {
    my ($timeout) = @_;
    AllowPriv (SE_SHUTDOWN_NAME, 1)
        or &writeLogfile($log,"Unable to AllowPriv SE_SHUTDOWN_NAME: $^E",1,"E") and exit 6;
		

    print "$0 is bouncing the system\n";
    InitiateSystemShutdown ('', "$0: Rebooting...", $timeout, 1, 1)
        or &writeLogfile($log,"Unable to InitiateSystemShutdown: $^E",1,"E") and exit 6;
    stop ();
}

# Check if we have administrative privileges.
sub are_we_administrator () {
    # See if we can enable the "take ownership" privilege.  This is
    # just a poor approximation to what we really want to know, which
    # is (usually) whether we can install software.
    return AllowPriv (SE_TAKE_OWNERSHIP_NAME, 1)
        && AllowPriv (SE_TAKE_OWNERSHIP_NAME, 0);
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

# Get Windows version as a canonical string, like "win2ksp4".
sub get_windows_version () {
    my $ver_key = "LMachine/SOFTWARE/Microsoft/Windows NT/CurrentVersion";

    my $pn_key = "$ver_key//ProductName";
    my $product_name = $reg{$pn_key};
    defined $product_name
        or &writeLogfile($log,"Unable to get $pn_key: $^E",1,"E") and exit 6;
    my $csd_key = "$ver_key//CSDVersion";
    my $csd_version = (exists $reg{$csd_key} ? $reg{$csd_key} : '');
    defined $csd_version
        or &writeLogfile($log,"Unable to get $csd_key: $^E",1,"E") and exit 6;

    my $os;
    if ($product_name eq 'Microsoft Windows 2000') {
        $os = 'win2k';
    }
    elsif ($product_name eq 'Microsoft Windows XP') {
        $os = 'winxp';
    }
    elsif ($product_name =~ m/Windows Server.*(2003)/) {
        $os = 'ws2k3';
    }
    elsif ($product_name =~ m/Vista/) {
        $os = 'vista';
    }
    elsif ($product_name =~ m/Windows Server.*(2008)/) {
        $os = 'ws2k8';
    }
    elsif ($product_name =~ m/Windows 7/) {
        $os = 'win7';
    }
    else {
		&writeLogfile($log,"Unrecognized $pn_key: $product_name",1,"E") and exit 6;
    }

    my $sp;
    if ($csd_version eq '') {
        $sp = '';
    }
    # Get a version number (only works up to 9)
    elsif ($csd_version =~ /(\d+)/) {
        $sp = "sp$1";
    }
    else {
		&writeLogfile($log,"Unrecognized $csd_key: $csd_version",1,"E") and exit 6;
    }

    return "$os$sp";
}

# Get a handle to the SWbemServices object for this machine.
my $wmi ;

if($^O ne 'linux'){
	$wmi = Win32::OLE->GetObject ('WinMgmts:');
}
# Get the three-letter acronym for the language of the running OS.
sub get_windows_language () {
    use Win32::OLE;
    # Bomb out completely if COM engine encounters any trouble.
    Win32::OLE->Option ('Warn' => 3);

    # Get the SWbemObjectSet of Win32_OperatingSystem instances.
    my $os_instances = $wmi->InstancesOf ('Win32_OperatingSystem');

    # Convert set to Perl array.
    my @oses = Win32::OLE::Enum->All ($os_instances);

    scalar @oses == 1
        or &writeLogfile($log,"Internal error (too many OS objects in get_windows_language)",1,"E") and exit 6;

    # See OSLanguage property in
    # <http://msdn.microsoft.com/library/en-us/wmisdk/wmi/win32_operatingsystem.asp>.
    # See also <http://www.microsoft.com/globaldev/nlsweb> and
    # <http://www.microsoft.com/globaldev/reference/winxp/langtla.mspx>.

    my %lang_table = (
                      0x0401 => 'ara',
                      0x0404 => 'cht',
                      0x0405 => 'csy',
                      0x0406 => 'dan',
                      0x0407 => 'deu',
                      0x0408 => 'ell',
                      0x0409 => 'enu',
                      0x040a => 'esp',
                      0x040b => 'fin',
                      0x040c => 'fra',
                      0x040d => 'heb',
                      0x040e => 'hun',
                      0x0410 => 'ita',
                      0x0411 => 'jpn',
                      0x0412 => 'kor',
                      0x0413 => 'nld',
                      0x0414 => 'nor',
                      0x0415 => 'plk',
                      0x0416 => 'ptb',
                      0x0418 => 'rom',
                      0x0419 => 'rus',
                      0x041d => 'sve',
                      0x041f => 'trk',
                      0x0804 => 'chs',
                      0x0816 => 'ptg',
                      0x0c0a => 'esn',
                      );

    my $langid = $oses[0]->OSLanguage;
    (defined $lang_table{$langid})
        or die sprintf "Unknown language ID 0x%04X", $langid;

    return $lang_table{$langid};
}

# Get the name of the local Administrators group, which varies by
# language.
sub get_administrators_group () {
    # Lookup by well-known SID.  See
    # <http://support.microsoft.com/?id=243330> and
    # <http://msdn.microsoft.com/library/en-us/wmisdk/wmi/win32_sid.asp>.

    my $admin_sid = $wmi->Get ('Win32_SID.SID="S-1-5-32-544"');
    return $admin_sid->{'AccountName'};
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
            # If the to-do list is not empty, arrange to run ourselves
            # after reboot.
            #my $next_cmd = peek_todo ();
            #defined $next_cmd
            #    and run_ourselves_at_logon ();
            reboot (5);
            die 'Internal error';
        }
        elsif ($cmd =~ /^\.expect-reboot\s+(.*)$/) {
            my $new_cmd = $1;
            # If the to-do list is not empty, arrange to run ourselves
            # after reboot.
            #my $next_cmd = peek_todo ();
            #defined $next_cmd
            #    and run_ourselves_at_logon ();
            do_cmd ($new_cmd);
			&writeLogfile($log,"Expecting previous command to reboot; exiting.",1,"!") and exit 0;

        }
        elsif ($cmd =~ /^\.reboot-on\s+(\d+)\s+(.*)$/) {
            my ($err_to_reboot, $new_cmd) = ($1, $2);
            my $status = do_cmd ($new_cmd, 1);

            if ($status == $err_to_reboot << 8) {

				&writeLogfile($log,"$new_cmd exited status $err_to_reboot; rebooting.",1,"!") ;
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
            my $real_status = $status >> 8;

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
	print "Start running:  $cmd\n";
#	my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
#	$mon += 1;
#	$mon = ($mon < 10)?"0$mon":$mon;
#	$mday = ($mday < 10)?"0$mday":$mday;
	
        my $status = system $cmd;
	#my ($sec2,$min2,$hour2) = localtime(time);
    #	my @old = read_file ($log);
	#write_file($log, ((1900+$year)."/$mon/$mday $hour:$min:$sec -> $hour2:$min2:$sec2, status $status,\tRunning:$cmd"), @old);
	&writeLogfile($log,"Stop running: $cmd, status $status",0,"-");
	$ret = $status;
    }

    defined $ret
        or &writeLogfile($log,"Internal error. Unexpected exit code ($ret) from $cmd",1,"E") and exit 6;

    unless ($no_bomb) {
        while ($ret != 0) {
            print "$cmd failed, status ", $ret >> 8, ' (', $ret % 256, ')', "\n";

            if ($errorhandle =~ m/^abort$/i) {
				push_todo($cmd);	# save command
				&writeLogfile($log,"$cmd exit with status $ret. Aborting.",1,"E");
				exit 6;
            #    die "Aborting.\n";
            }
            elsif ($errorhandle =~ m/^retry.*$/i) {
				if($ENV{'_TODO_RETRY'} != 0){
					$ENV{'_TODO_RETRY'} = $ENV{'_TODO_RETRY'} - 1;
					#print "\n";
					&writeLogfile($log,"$cmd exit with status $ret. Retrying (".($ENV{'_TODO_RETRY'}+1)." times).",1,"!");
					return do_cmd ($cmd);
				}elsif($errorhandle =~ m/^retry&skip$/i){
					$ugly = "skip";
					$ENV{'_TODO_RETRY'} = $errorretries;
				}elsif($errorhandle =~ m/^retry(&abort)*$/i){
					$ENV{'_TODO_RETRY'} = $errorretries;
					push_todo($cmd);	# save command
					&writeLogfile($log,"$cmd exit with status $ret. Aborting.",1,"E");
					exit 6;
            	}elsif($errorhandle =~ m/^retry&ignore$/i){
					$ugly = "ignore";
					$ENV{'_TODO_RETRY'} = $errorretries;
            	}
			}
			if($errorhandle =~ m/^ignore$/i or $ugly eq "ignore") {
				$ugly =  "";
                &writeLogfile($log,"$cmd exit with status $ret. Ignoring.",1,"W");
                $ret = 0;
            }elsif ($errorhandle =~ m/^skip$/i or $ugly eq "skip") {
				$ugly =  "";
				&writeLogfile($log,"$cmd exit with status $ret. Skipping $cmd.",1,"W");
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

exists $opts{'user'} || are_we_administrator ()
    or &writeLogfile($log,"Not Administrator and --user not supplied",1,"E") and exit 6;

if (exists $opts{'go'}) {
    @ARGV == 0
        or pod2usage (2);
	
    # Prevent re-entrancy.
    (exists $ENV{'_IN_TODO'})
        and exit 0;
    $ENV{'_IN_TODO'} = 'yes';

    # Add "bin" and "scripts" directories to PATH.
	
    $ENV{'PATH'} = "$path_to_bin;$path_to_scripts;$local_scripts_dir;$ENV{'PATH'}";

    # Set handy "WINVER" environment variable.
    $ENV{'WINVER'} = get_windows_version ();

    # Set handy "WINLANG" environment variable.
    $ENV{'WINLANG'} = get_windows_language ();

    # Set handy "Z_PATH" environment variable.
	$ENV{'Z'} = $z;
    $ENV{'Z_PATH'} = $z;
    #$ENV{'Z_PATH'} = get_drive_path ($z);

    # Set "Administrators" environment variable to local
    # Administrators group.
    $ENV{'Administrators'} = get_administrators_group ();



    while (defined (my $cmd = pop_todo ())) {
        do_cmd ($cmd);
    }
}
else {
    # Default behavior is to push one or more commands onto the todo
    # list.
    @ARGV > 0
        or pod2usage (2);
    push_todo (@ARGV);
}

exit 0;

__END__

=head1 NAME

todo.pl - Manage the to-do list

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
