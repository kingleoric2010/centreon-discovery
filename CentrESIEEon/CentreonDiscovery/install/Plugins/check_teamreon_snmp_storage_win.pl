#! /usr/bin/perl -w
###################################################################
# Oreon is developped with GPL Licence 2.0 
#
# GPL License: http://www.gnu.org/licenses/old-licenses/gpl-2.0.txt
#
# Developped by : Julien Mathis - Romain Le Merlus 
#                 Christophe Coraboeuf - Sugumaran Mathavarajan
#
###################################################################
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
# 
#    For information : contact@merethis.com
####################################################################
#
# Script init
#

use strict;
use Net::SNMP qw(:snmp);
use FindBin;
use lib "$FindBin::Bin";
use lib "/usr/lib/nagios/plugins";
use utils qw($TIMEOUT %ERRORS &print_revision &support);

if (eval "require centreon" ) {
    use centreon qw(get_parameters);
    use vars qw(%centreon);
    %centreon = get_parameters();
} else {
	print "Unable to load centreon perl module\n";
    exit $ERRORS{'UNKNOWN'};
}
use vars qw($PROGNAME);
use Getopt::Long;
use vars qw($opt_V $opt_t $opt_P $opt_h $opt_v $opt_f $opt_C $opt_d $opt_k $opt_u $opt_p $opt_n $opt_w $opt_c $opt_H $opt_s @test);

# Plugin var init

my ($hrStorageDescr, $hrStorageAllocationUnits, $hrStorageSize, $hrStorageUsed);
my ($AllocationUnits, $Size, $Used);
my ($tot, $used, $pourcent, $return_code);

$PROGNAME = "$0";
sub print_help ();
sub print_usage ();

Getopt::Long::Configure('bundling');
GetOptions
    ("h"   => \$opt_h, "help"         => \$opt_h,
     "u=s"   => \$opt_u, "username=s" => \$opt_u,
     "p=s"   => \$opt_p, "password=s" => \$opt_p,
     "k=s"   => \$opt_k, "key=s"      => \$opt_k,
     "P=s"   => \$opt_P, "--snmp-port=s" => \$opt_P,
     "V"   => \$opt_V, "version"      => \$opt_V,
     "s"   => \$opt_s, "show"         => \$opt_s,
     "v=s" => \$opt_v, "snmp=s"       => \$opt_v,
     "C=s" => \$opt_C, "community=s"  => \$opt_C,
     "d=s" => \$opt_d, "disk=s"       => \$opt_d,
     "n"   => \$opt_n, "name"         => \$opt_n,
     "w=s" => \$opt_w, "warning=s"    => \$opt_w,
     "c=s" => \$opt_c, "critical=s"   => \$opt_c,
     "H=s" => \$opt_H, "hostname=s"   => \$opt_H, 
     "t=s"   => \$opt_t);


if ($opt_V) {
    print_revision($PROGNAME,'$Revision: 1.2 $');
    exit $ERRORS{'OK'};
}
if (!defined($opt_P)) {
	$opt_P = 161;
}
if ($opt_h) {
	print_help();
	exit $ERRORS{'OK'};
}
if (!$opt_H) {
	print_usage();
	exit $ERRORS{'OK'};
}

if ($opt_n && !$opt_d) {
    print "Option -n (--name) need option -d (--disk)\n";
    exit $ERRORS{'UNKNOWN'};
}
my $snmp = "1";
$snmp = $opt_v if ($opt_v && $opt_v =~ /^[0-9]$/);

if ($snmp eq "3") {
	if (!$opt_u) {
		print "Option -u (--username) is required for snmpV3\n";
		exit $ERRORS{'OK'};
	}
	if (!$opt_p && !$opt_k) {
		print "Option -k (--key) or -p (--password) is required for snmpV3\n";
		exit $ERRORS{'OK'};
	} elsif ($opt_p && $opt_k) {
		print "Only option -k (--key) or -p (--password) is needed for snmpV3\n";
		exit $ERRORS{'OK'};
	}
}

$opt_C = "public" if (!$opt_C);
$opt_d = 2 if (!$opt_d);

($opt_d) || ($opt_d = shift) || ($opt_d = 2);

my $partition = 0;
if ($opt_d =~ /([0-9]+)/ && !$opt_n){
    $partition = $1;
} elsif (!$opt_n){
    print "Unknown -d number expected... or it doesn't exist, try another disk - number\n";
    exit $ERRORS{'UNKNOWN'};
}
if (!$opt_c) {
	$opt_c = 95;
}
if (!$opt_w) {
	$opt_w = 90;
}
my $critical = 95;
if ($opt_c && $opt_c =~ /^[0-9]+$/) {
    $critical = $opt_c;
}
my $warning = 90;
if ($opt_w && $opt_w =~ /^[0-9]+$/) {
    $warning = $opt_w;
}

if ($critical <= $warning){
    print "(--crit) must be superior to (--warn)";
    print_usage();
    exit $ERRORS{'OK'};
}


my $name = $0;
$name =~ s/\.pl.*//g;

# Plugin snmp requests
my $OID_hrStorageDescr = "";
if (defined($opt_t) && ($opt_t eq "AIX" || $opt_t eq "AS400")){
	$OID_hrStorageDescr = ".1.3.6.1.2.1.25.3.8.1.2";
} else { 
	$OID_hrStorageDescr = $centreon{MIB2}{HR_STORAGE_DESCR};
}
my $OID_hrStorageAllocationUnits = $centreon{MIB2}{HR_STORAGE_ALLOCATION_UNITS};
my $OID_hrStorageSize = $centreon{MIB2}{HR_STORAGE_SIZE};
my $OID_hrStorageUsed = $centreon{MIB2}{HR_STORAGE_USED};

# create a SNMP session
my ($session, $error);
if ($snmp eq "1" || $snmp eq "2") {
	($session, $error) = Net::SNMP->session(-hostname => $opt_H, -community => $opt_C, -version => $snmp, -port => $opt_P);
	if (!defined($session)) {
	    print("UNKNOWN: SNMP Session : $error\n");
	    exit $ERRORS{'UNKNOWN'};
	}
} elsif ($opt_k) {
    ($session, $error) = Net::SNMP->session(-hostname => $opt_H, -version => $snmp, -username => $opt_u, -authkey => $opt_k, -port => $opt_P);
	if (!defined($session)) {
	    print("UNKNOWN: SNMP Session : $error\n");
	    exit $ERRORS{'UNKNOWN'};
	}
} elsif ($opt_p) {
    ($session, $error) = Net::SNMP->session(-hostname => $opt_H, -version => $snmp,  -username => $opt_u, -authpassword => $opt_p, -port => $opt_P);
	if (!defined($session)) {
	    print("UNKNOWN: SNMP Session : $error\n");
	    exit $ERRORS{'UNKNOWN'};
	}
}
$session->translate(Net::SNMP->TRANSLATE_NONE) if (defined($session));


#getting partition using its name instead of its oid index
if ($opt_n) {
    my $result = $session->get_table(Baseoid => $OID_hrStorageDescr);
    if (!defined($result)) {
        printf("ERROR: hrStorageDescr Table : %s.\n", $session->error);
        $session->close;
        exit $ERRORS{'UNKNOWN'};
    }
    my $expr = "";
    if ($opt_d =~ m/^[A-Za-z]:/) {
		$opt_d =~ s/\\/\\\\/g;
		$expr = "^$opt_d";
    }elsif ($opt_d =~ m/^\//) {
		$expr = "$opt_d\$";
    }else {
		$expr = "$opt_d";
    }
    foreach my $key ( oid_lex_sort(keys %$result)) {
        if (defined($opt_t) && $opt_t eq "AS400"){
		$result->{$key} =~ s/\ //g;
	}
	if ($result->{$key} =~ m/$expr/) {
	   	 	my @oid_list = split (/\./,$key);
	   	 	$partition = pop (@oid_list) ;
		}
    }
}

if ($opt_s) {
    # Get description table
    my $result = $session->get_table(
        Baseoid => $OID_hrStorageDescr
    );

    if (!defined($result)) {
        printf("ERROR: hrStorageDescr Table : %s.\n", $session->error);
        $session->close;
        exit $ERRORS{'UNKNOWN'};
    }

    foreach my $key ( oid_lex_sort(keys %$result)) {
        my @oid_list = split (/\./,$key);
        my $index = pop (@oid_list) ;
        print "hrStorage $index :: $$result{$key}\n";
    }
	exit $ERRORS{'OK'};
}


my $result = $session->get_request(
                                   -varbindlist => [$OID_hrStorageDescr.".".$partition  ,
                                                    $OID_hrStorageAllocationUnits.".".$partition  ,
                                                    $OID_hrStorageSize.".".$partition,
                                                    $OID_hrStorageUsed.".".$partition
                                                    ]
                                   );
if (!defined($result)) {
    printf("ERROR:  %s.\n", $session->error);
    if ($opt_n) { print(" - You must specify the disk name when option -n is used");}
    print ".\n";
    $session->close;
    exit $ERRORS{'UNKNOWN'};
}

$hrStorageDescr  =  $result->{$OID_hrStorageDescr.".".$partition };
$AllocationUnits  =  $result->{$OID_hrStorageAllocationUnits.".".$partition };
$Size  =  $result->{$OID_hrStorageSize.".".$partition };
$Used  =  $result->{$OID_hrStorageUsed.".".$partition };


# Plugins var treatment

if (!$Size){
    print "CRITICAL - no output (-p number expected... it doesn't exist, try another disk - number\n";
    exit $ERRORS{'CRITICAL'};
}

if (($Size =~  /([0-9]+)/) && ($AllocationUnits =~ /([0-9]+)/)){
	
	if ($hrStorageDescr =~ /\:/){
        my @tab = split(/\:/, $hrStorageDescr);
        $hrStorageDescr = $tab[0] . ":";
    }
	
    if (!$Size){
        print "The number of the option -p is not a hard drive\n";
        exit $ERRORS{'CRITICAL'};
    }
    $tot = 1;
    $tot = $Size * $AllocationUnits;
    if (!$tot){$tot = 1;}
    $used = $Used * $AllocationUnits;
    $pourcent = ($used * 100) / $tot;

    if (length($pourcent) > 2){
        @test = split (/\./, $pourcent);
        $pourcent = $test[0];
    }
    my $lastTot = $tot;
    $tot = $tot / 1073741824;
    $Used = ($Used * $AllocationUnits) / 1073741824;
    
    # Plugin return code
    
    if ($pourcent >= $critical){
        print "CRITICAL - ";
        $return_code = 2;
    } elsif ($pourcent >= $warning){
        print "WARNING - ";
        $return_code = 1;
    } else {
        print "OK - ";
        $return_code = 0;
    }

    if ($hrStorageDescr){
        $hrStorageDescr =~ s/\ //g if (defined($opt_t) && $opt_t eq "AS400");
        print $hrStorageDescr . " TOTAL: ";
        printf("%.3f", $tot);
        print " Go USED: " . $pourcent . "% : ";
        printf("%.3f", $Used);
        print " Go";
        my $size_o = $Used * 1073741824;
        my $warn = $opt_w * $size_o;
        my $crit = $opt_c * $size_o;
        print "|size=".$lastTot."o used=".$size_o."o;".$warn.";".$crit;
        print "\n";
        exit $return_code;
    } else {
        print "TOTAL: ";
        printf("%.3f", $tot);
        print " Go USED: " . $pourcent . "% : ";
        printf("%.3f", $Used);
        print " Go\n";
        exit $return_code;
    }
} else {
    print "CRITICAL - no output (-d number expected... it doesn't exist, try another disk - number\n";
    exit $ERRORS{'CRITICAL'};
}

sub print_usage () {
    print "\nUsage:\n";
    print "$PROGNAME\n";
    print "   -H (--hostname)   Hostname to query - (required)\n";
    print "   -C (--community)  SNMP read community (defaults to public,\n";
    print "                     used with SNMP v1 and v2c\n";
    print "   -v (--snmp_version)  1 for SNMP v1 (default)\n";
    print "                        2 for SNMP v2c\n";
    print "   -d (--disk)       Set the disk (number expected) ex: 1, 2,... (defaults to 2 )\n";
    print "   -n (--name)       Allows to use disk name with option -d instead of disk oid index\n";
    print "                     (ex: -d \"C:\" -n, -d \"E:\" -n, -d \"Swap Memory\" -n, -d \"Real Memory\" -n\n";
    print "                     (choose an unique expression for each disk)\n";
    print "   -s (--show)       Describes all disk (debug mode)\n";
    print "   -w (--warn)       Signal strength at which a warning message will be generated\n";
    print "                     (default 80)\n";
    print "   -c (--crit)       Signal strength at which a critical message will be generated\n";
    print "                     (default 95)\n";
    print "   -V (--version)    Plugin version\n";
    print "   -h (--help)       usage help\n";

}

sub print_help () {
    print "##############################################\n";
    print "#    Copyright (c) 2004-2007 Centreon        #\n";
    print "#    Bugs to http://bugs.oreon-project.org/  #\n";
    print "##############################################\n";
    print_usage();
    print "\n";
}
