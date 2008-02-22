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
}

1;

