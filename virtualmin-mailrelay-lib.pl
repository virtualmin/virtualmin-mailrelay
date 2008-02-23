# Common functions needed for forwarded mail filtering

do '../web-lib.pl';
&init_config();
do '../ui-lib.pl';
&foreign_require('virtual-server', 'virtual-server-lib.pl');
%access = &get_module_acl();

sub can_edit_relay
{
local ($dname) = @_;
if ($access{'dom'} eq '*') {
	return 1;
	}
else {
	return &indexof($dname, split(/\s+/, $access{'dom'})) >= 0;
	}
}

# get_relay_destination(domain)
# Returns the SMTP server to relay email to for some domain
sub get_relay_destination
{
local ($dname) = @_;
&virtual_server::require_mail();
if ($virtual_server::config{'mail_system'} == 0) {
	# From SMTP transport
	local $trans = &postfix::get_maps("transport_maps");
	local ($old) = grep { $_->{'name'} eq $dname } @$trans;
	if ($old) {
		if ($old->{'value'} =~ /^\S+:\[(\S+)\]$/) {
			return $2;
			}
		elsif ($old->{'value'} =~ /^\S+:(\S+)$/) {
			return $2;
			}
		else {
			return $old->{'value'};
			}
		}
	return undef;
	}
elsif ($virtual_server::config{'mail_system'} == 1) {
	# Get mailertable entry
	&foreign_require("sendmail", "mailers-lib.pl");
	local $conf = &sendmail::get_sendmailcf();
	local $mfile = &sendmail::mailers_file($conf);
	local ($mdbm, $mtype) = &sendmail::mailers_dbm($conf);
	local @mailers = &sendmail::list_mailers($mfile);
	local ($old) = grep { $_->{'domain'} eq $dname } @mailers;
	if ($old) {
		if ($old->{'dest'} =~ /^\[(\S+)\]$/) {
			return $1;
			}
		else {
			return $old->{'dest'};
			}
		}
	}
return undef;	# Not found??
}

# save_relay_destination(domain, server)
# Updates the SMTP server to relay email to for some domain
sub save_relay_destination
{
local ($dname, $server) = @_;
&virtual_server::require_mail();
&obtain_lock_virtualmin_mailrelay();
if ($virtual_server::config{'mail_system'} == 0) {
	# Update SMTP transport
	local $trans = &postfix::get_maps("transport_maps");
	local ($old) = grep { $_->{'name'} eq $dname } @$trans;
	if ($old) {
		local $nw = { %$old };
		if ($old->{'value'} =~ /^(\S+):\[(\S+)\]$/) {
			$nw->{'value'} = "$1:[$server]";
			}
		elsif ($old->{'value'} =~ /^(\S+):(\S+)$/) {
			$nw->{'value'} = "$1:$server";
			}
		else {
			$nw->{'value'} = $server;
			}
		&postfix::modify_mapping("transport_maps", $old, $nw);
		&postfix::regenerate_any_table("transport_maps");
		}
	return undef;
	}
elsif ($virtual_server::config{'mail_system'} == 1) {
	# Get mailertable entry
	&foreign_require("sendmail", "mailers-lib.pl");
	local $conf = &sendmail::get_sendmailcf();
	local $mfile = &sendmail::mailers_file($conf);
	local ($mdbm, $mtype) = &sendmail::mailers_dbm($conf);
	local @mailers = &sendmail::list_mailers($mfile);
	local ($old) = grep { $_->{'domain'} eq $dname } @mailers;
	if ($old) {
		local $nw = { %$old };
		if ($old->{'dest'} =~ /^\[(\S+)\]$/) {
			$nw->{'dest'} = "[$server]";
			}
		else {
			$nw->{'dest'} = $server;
			}
		&sendmail::modify_mailer($old, $nw, $mfile,
					 $mdbm, $mtype);
		}
	}
&release_lock_virtualmin_mailrelay();
}

sub obtain_lock_virtualmin_mailrelay
{
&virtual_server::obtain_lock_anything();
if ($mail::got_lock_virtualmin_mailrelay == 0) {
	&virtual_server::require_mail();
	@main::got_lock_virtualmin_mailrelay_files = ( );
	if ($virtual_server::config{'mail_system'} == 0) {
		# Lock transport file
		local @tv = &postfix::get_maps_types_files("transport_maps");
		push(@main::got_lock_virtualmin_mailrelay_files,
		     map { $_->[1] } @tv);
		}
	elsif ($virtual_server::config{'mail_system'} == 1) {
		# Lock mailertable file
		local $mfile = &sendmail::mailers_file(
				&sendmail::get_sendmailcf());
		push(@main::got_lock_virtualmin_mailrelay_files, $mfile);
		}
	@main::got_lock_virtualmin_mailrelay_files =
		grep { /^\// } @main::got_lock_virtualmin_mailrelay_files;
	foreach my $f (@main::got_lock_virtualmin_mailrelay_files) {
		&lock_file($f);
		}
	}
$mail::got_lock_virtualmin_mailrelay++;
}

sub release_lock_virtualmin_mailrelay
{
if ($main::got_lock_virtualmin_mailrelay == 1) {
	foreach my $f (@main::got_lock_virtualmin_mailrelay_files) {
		&unlock_file($f);
		}
	}
$main::got_lock_virtualmin_mailrelay-- if ($main::got_lock_virtualmin_mailrelay);
}

1;

