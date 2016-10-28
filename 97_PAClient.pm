package main;
use strict;
use warnings;

my $PAClient_LogLevelDebug = 1;
my $PAClient_LogLevelNormal = 1;
my $PAClient_LogLevelCritical =1;

my $PAClient_standard_interval = 10;

my %PAClient_gets = (
	"tbd"	=> "x"
);

my %PAClient_sets = (
    "desired-master"   => ""
);

	   
sub PAClient_Initialize($) {
    my ($hash) = @_;

    $hash->{DefFn}      = 'PAClient_Define';
    $hash->{UndefFn}    = 'PAClient_Undef';
    $hash->{SetFn}      = 'PAClient_Set';
    $hash->{GetFn}      = 'PAClient_Get';
    $hash->{AttrFn}     = 'PAClient_Attr';
    $hash->{ReadFn}     = 'PAClient_Read';
	$hash->{Match}     = ".*";
    $hash->{AttrList} =
          "IODev startcmd stopcmd interval "
        . $readingFnAttributes;
}

sub PAClient_Define($$) {
    my ($hash, $def) = @_;
    my @a = split('[ \t]+', $def);
	if (@a != 3) {
		my $msg = "wrong syntax: define <name> PAClient <host/ip>";
	  	Log3 undef, 2, $msg;
	  	return $msg;
	}
    $hash->{name}  = $a[0];
    $hash->{ip} = $a[2]; 
    Log $PAClient_LogLevelNormal, "PAClient: Device $a[0] defined.";
    readingsSingleUpdate($hash,"state","defined",1);
    RemoveInternalTimer($hash);
    InternalTimer(gettimeofday()+5, "PAServer_processCmd", $hash, 0);  # initiate the regular update process
	AssignIoPort($hash);
    return undef;
}

sub PAClient_Undef($$) {
    my ($hash, $arg) = @_; 
    # TODO: delete modules combined and tunnels
    RemoveInternalTimer($hash);
    BlockingKill($hash->{helper}{RUNNING_PID}) if(defined($hash->{helper}{RUNNING_PID}));
	IOWrite ($hash, $hash->{name},"deleted");
    return undef;
}

sub PAClient_Get($@) {
	my ($hash, @param) = @_;
	return '"get PAClient" needs at least one argument' if (int(@param) < 2);
	
	my $name = shift @param;
	my $opt = shift @param;
	if(!$PAClient_gets{$opt}) {
		my @cList = keys %PAClient_gets;
		return "Unknown argument $opt, choose one of " . join(" ", @cList);
	}
	return "to be defined";
}

sub PAClient_Set($@) {
	my ($hash, @param) = @_;
	
	return '"set PAClient" needs at least one argument' if (int(@param) < 2);
	
	my $name = shift @param;
	my $opt = shift @param;
	my $value = join("", @param);
	
	if(!defined($PAClient_sets{$opt})) {
		my @cList = keys %PAClient_sets;
		return "Unknown argument $name $opt $value, choose one of " . join(" ", @cList);
	}
	if($opt eq "desired-master"){
		if($value eq $name){
			return "Cant set master to self";
		}
		if($value eq "none"){
			delete $hash->{DESIRED_MASTER};
			IOWrite ($hash, $hash->{name},"DESIRED_MASTER none");
			return undef;
		}
		$hash->{DESIRED_MASTER}=$value;
		IOWrite ($hash, $hash->{name},"DESIRED_MASTER $value");
		return undef;
	}
	
	return "not yet implemented";
}





1;
