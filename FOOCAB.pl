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
    if (defined $host && ($vars[$i] eq "HOSTNAME")) {
	$hi = $i;
    }
    elsif (defined $node && ($vars[$i] eq "NODE")) {
	$ni = $i;
    }
    elsif ($vars[$i] eq "DHCPSTART") {
	$di = $i;
    }
}

my $logo = undef;
my $bridge = undef;
my $device = undef;

while(<NODEDB>) {
    chomp;
    @vals = split /\t/;

    if ((defined $hi && ($vals[$hi] eq $host)) ||
	(defined $ni && ($vals[$ni] eq $node)))
    {
	my $masklen = undef;
	my $localaddr = undef;
	my $privaddr = undef;
	my $privmasklen = undef;

	for ($i = 0 ; $i < @vars ; $i++)
	{
            # provide an overridable default value for DHCPSTART
	    if ($i == $di && ((not defined($vals[$i])) || ($vals[$i] eq ""))) { 
		$vals[$i] = 5;
	    }
   
	    print SED "s/PTP_$vars[$i]_PTP/$vals[$i]/g\n";
	    if ($vars[$i] eq "PUBMASKLEN") {
		$masklen = $vals[$i];
	    }
	    if ($vars[$i] eq "PUBADDR") {
		$localaddr = $vals[$i];
	    }
	    if ($vars[$i] eq "LOGOFILE") {
		$logo = $vals[$i];
	    }
	    if ($vars[$i] eq "BRIDGE") {
		$bridge = $vals[$i];
	    }
	    if ($vars[$i] eq "DEVICE") {
		$device = $vals[$i];
	    }
	    if ($vars[$i] eq "PRIVADDR") {
		$privaddr = $vals[$i];
	    }
	    if ($vars[$i] eq "PRIVMASKLEN") {
		$privmasklen = $vals[$i];
	    }
	    
	}

	print "DEVICE=$device\n";

	if($device eq "WGT") {
	    print SED "s/PTP_WANIFACE_PTP/eth0.1/g\n";
	    print SED "s/PTP_PRIVIFACE_PTP/eth0.0/g\n";
	} elsif ($device eq "ALIX") {
	    print SED "s/PTP_WANIFACE_PTP/eth0/g\n";
	    print SED "s/PTP_PRIVIFACE_PTP/eth2/g\n";
	}   

	(defined $masklen && defined $localaddr) || die "Not enough information to compute network!";

	my $ip = NetAddr::IP::Lite->new("$localaddr/$masklen");
	my $network = $ip->network();
	my $netaddr = $network->addr();
	my $mask = $ip->mask();

	print SED "s/PTP_PUBNET_PTP/$netaddr/g\n";
	print SED "s/PTP_PUBNETMASK_PTP/$mask/g\n";
	if ($device eq "WGT") {
	    print SED "s/PTP_PUBIFACE_PTP/ath0/g\n";
	} elsif ($device eq "ALIX") {
	    print SED "s/PTP_PUBIFACE_PTP/eth1/g\n";
	}

	if ($bridge) {
	    print SED "s/PTP_LOCALIFACE_PTP/br-lan/g\n";
	} else {
	    $ip = NetAddr::IP::Lite->new("$privaddr/$privmasklen");
	    $network = $ip->network();
	    $netaddr = $network->addr();
	    $mask = $ip->mask();

	    if ($device eq "WGT") {
		print SED "s/PTP_LOCALIFACE_PTP/ath0/g\n";
	    } elsif ($device eq "ALIX") {
		print SED "s/PTP_LOCALIFACE_PTP/eth1/g\n";
	    }
	    print SED "s/PTP_PRIVNET_PTP/$netaddr/g\n";
	    print SED "s/PTP_PRIVNETMASK_PTP/$mask/g\n";
	}
    }
}

open(FILES,"find etc usr root -type f |");

while(<FILES>) {
    chomp;
    my $src = $_;
    my @path = split('/',$src);
    my $fname = pop @path;
    my $outdir = join('/',"output",@path);
    my $dest = join('/',"output",@path,$fname);

    # print "source = $src ; outdir = $outdir ; dest = $dest\n";

    ($dev,$ino,$mode,$nlink,$uid,$gid,$rdev,$size,$atime,$mtime,$ctime,$blksize,$blocks) = stat($src);

    unless (-d $outdir) { system("mkdir -p $outdir"); }

    print "sed -f foocab.sed < $src > $dest\n";

    system("sed -f foocab.sed < $src > $dest");

    chmod($mode,$dest);
    chown($uid,$gid,$dest);
}

if ($bridge) {
    open(BRIDGE,"find bridge -type f |");

    while(<BRIDGE>) {
	chomp;
	my $src = $_;
	my @path = split('/',$src);
	my $fname = pop @path;
	shift @path; # scrape off "bridge" from path
	my $outdir = join('/',"output",@path);
	my $dest = join('/',"output",@path,$fname);
	
	# print "source = $src ; outdir = $outdir ; dest = $dest\n";
	
	($dev,$ino,$mode,$nlink,$uid,$gid,$rdev,$size,$atime,$mtime,$ctime,$blksize,$blocks) = stat($src);
	
	unless (-d $outdir) { system("mkdir -p $outdir"); }
	
	print "sed -f foocab.sed < $src > $dest\n";

	system("sed -f foocab.sed < $src > $dest");
	
	chmod($mode,$dest);
	chown($uid,$gid,$dest);
    }
}

if ($device eq "WGT") {
    # remove redundant interface, in cases of bridging
    system("mv output/etc/config/network output/etc/config/network.orig ; sed 's/eth0.0 ath0/eth0.0/' output/etc/config/network.orig > output/etc/config/network ; rm output/etc/config/network.orig");
} elsif ($device eq "ALIX") {
    # if alix, remove the vlan configuration from etc/config/network
    # and delete the etc/config/wireless
    system("mv output/etc/config/network output/etc/config/network.orig ; tail -n +`grep -n '#### Loopback' output/etc/config/network.orig | cut -d: -f 1` output/etc/config/network.orig > output/etc/config/network ; rm output/etc/config/network.orig output/etc/config/wireless");
}
    

open(LINKS,"find etc usr root -type l |");

while(<LINKS>) {
    chomp;

    my $src = $_;
    my @path = split('/',$src);
    my $fname = pop @path;
    my $outdir = join('/',"output",@path);
    my $dest = join('/',"output",@path,$fname);

    unless (-d $outdir) { system("mkdir -p $outdir"); }

    print "cp -d $src $dest\n";

    system("cp -d $src $dest");
}

open(WWW,"find www -type f | grep -v nodes |");

while(<WWW>) {
    chomp;
    my $src = $_;
    my @path = split('/',$src);
    my $fname = pop @path;
    my $outdir = join('/',"output",@path);
    my $dest = join('/',"output",@path,$fname);

    # print "source = $src ; outdir = $outdir ; dest = $dest\n";

    ($dev,$ino,$mode,$nlink,$uid,$gid,$rdev,$size,$atime,$mtime,$ctime,$blksize,$blocks)
	= stat($src);

    unless (-d $outdir) { system("mkdir -p $outdir"); }

    print "sed -f foocab.sed < $src > $dest\n";

    system("sed -f foocab.sed < $src > $dest");

    chmod($mode,$dest);
    chown($uid,$gid,$dest);
}

if (defined($logo) && $logo ne "") {
    my $src = "www/images/nodes/$logo";

    print "cp -p $src output/www/images/$logo\n";

    system("cp -p $src output/www/images/$logo");
}
