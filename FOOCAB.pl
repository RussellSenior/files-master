#!/usr/bin/perl

use Getopt::Long;
use NetAddr::IP::Lite;

my $host;
my $node;

$result = GetOptions ("host=s" => \$host,
		      "node=s" => \$node);

open(NODEDB,"nodedb.txt");
open(SED,">foocab.sed");

$header = <NODEDB>;
chomp $header;

@vars = split /\t/, $header;

my $hi = undef;
my $ni = undef;
my $di = undef; # index of DHCPSTART

for ($i = 0 ; $i < @vars ; $i++)
{
    if (defined $host && ($vars[$i] eq "HOSTNAME"))
    {
	$hi = $i;
    }
    elsif (defined $node && ($vars[$i] eq "NODE"))
    {
	$ni = $i;
    }
    elsif ($vars[$i] eq "DHCPSTART")
    {
	$di = $i;
    }
}

while(<NODEDB>) {
    chomp;
    @vals = split /\t/;

    if ((defined $hi && ($vals[$hi] eq $host)) ||
	(defined $ni && ($vals[$ni] eq $node)))
    {
	my $masklen = undef;
	my $localaddr = undef;

	for ($i = 0 ; $i < @vars ; $i++)
	{
            # provide an overridable default value for DHCPSTART
	    if ($i == $di && not defined($vals[$i])) { 
		$vals[$i] = 5;
	    }
	       
	    print SED "s/PTP_$vars[$i]_PTP/$vals[$i]/g\n";
	    if ($vars[$i] eq "LOCALMASKLEN") {
		$masklen = $vals[$i];
	    }
	    if ($vars[$i] eq "LOCALADDR") {
		$localaddr = $vals[$i];
	    }
	}
	
	(defined $masklen && defined $localaddr) || die "Not enough information to compute network!";

	my $ip = NetAddr::IP::Lite->new("$localaddr/$masklen");
	my $network = $ip->network();
	my $netaddr = $network->addr();
	my $mask = $ip->mask();

	print SED "s/PTP_LOCALNET_PTP/$netaddr/g\n";
	print SED "s/PTP_LOCALNETMASK_PTP/$mask/g\n";

    }
}
