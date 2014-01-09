# Common functions needed for forwarded mail filtering

BEGIN { push(@INC, ".."); };
eval "use WebminCore;";
&init_config();
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

# can_domain_filter()
# Returns 1 if we can configure per-domain filtering
sub can_domain_filter
{
return $config{'scanner'} == 1 &&
       $config{'domains_file'};
}

# can_relay_port()
# Returns 1 if the destination can be in host:port format. Only true for
# Postfix currently.
sub can_relay_port
{
return $virtual_server::config{'mail_system'} == 0 ? 1 : 0;
}

# check_spam_filter()
# Checks if the configured spam filter is installed, and returns an error
# message if not.
sub check_spam_filter
{
if ($config{'scanner'} == 1) {
	# Check for MIMEdefang. This only works with Sendmail, and must be
	# setup and running.
	&virtual_server::require_mail();
	$virtual_server::config{'mail_system'} == 1 ||
		return $text{'defang_esendmail'};
	&foreign_require("sendmail", "features-lib.pl");
	local @feats = &sendmail::list_features();
	if (@feats) {
		local ($mdf) = grep {
		    $_->{'text'} =~ /INPUT_MAIL_FILTER.*mimedefang/ } @feats;
		$mdf || return &text('defang_efeature',
				     "<tt>$config{'sendmail_mc'}</tt>");
		}
	local @pids = &find_byname("mimedefang.pl");
	@pids || return $text{'defang_eprocess'};
	-r $config{'mimedefang_script'} || return &text('defang_escript',
		"<tt>$config{'mimedefang_script'}</tt>",
		"../config.cgi?$module_name");
	if ($config{'domains_file'}) {
		local $lref = &read_file_lines($config{'mimedefang_script'}, 1);
		local $found = 0;
		foreach my $l (@$lref) {
			$found++ if ($l =~ /\Q$config{'domains_file'}\E/);
			}
		$found || return &text('defang_efile',
			"<tt>$config{'mimedefang_script'}</tt>",
			"<tt>$config{'domains_file'}</tt>",
			"../config.cgi?$module_name");
		}
	return undef;
	}
else {
	return undef;
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
			return $1;
			}
		elsif ($old->{'value'} =~ /^\S+:\[(\S+)\]:(\d+)$/) {
			return $1.":".$2;
			}
		elsif ($old->{'value'} =~ /^\S+:(\S+)$/) {
			return $1;
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
	# Update Postfix SMTP transport
	local $trans = &postfix::get_maps("transport_maps");
	local ($old) = grep { $_->{'name'} eq $dname } @$trans;
	if ($old) {
		local $nw = { %$old };
		if ($old->{'value'} =~ /^(\S+):\[(\S+)\]$/) {
			my $lhs = $1;
			if ($server =~ /^(.*):(\d+)$/) {
				$nw->{'value'} = "$lhs:[$1]:$2";
				}
			else {
				$nw->{'value'} = "$lhs:[$server]";
				}
			}
		elsif ($old->{'value'} =~ /^(\S+):([^0-9 ]+)$/) {
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
	# Get Sendmail mailertable entry
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

# get_domain_filter(dname)
# Return 1 if relay filtering is enabled for a domain
sub get_domain_filter
{
local ($dname) = @_;
local $lref = &read_file_lines($config{'domains_file'}, 1);
return &indexoflc($dname, @$lref) >= 0 ? 1 : 0;
}

# save_domain_filter(dname, flag)
# Turns on or off  relay filtering for a domain
sub save_domain_filter
{
local ($dname, $filter) = @_;
local $lref = &read_file_lines($config{'domains_file'});
local $idx = &indexoflc($dname, @$lref);
if ($idx >= 0 && !$filter) {
	# Remove from file
	splice(@$lref, $idx, 1);
	}
elsif ($idx < 0 && $filter) {
	# Add to file
	push(@$lref, $dname);
	}
&flush_file_lines($config{'domains_file'});
}

# obtain_lock_virtualmin_mailrelay()
# Lock the Sendmail or Postfix mail relay file
sub obtain_lock_virtualmin_mailrelay
{
if (defined(&virtual_server::obtain_lock_anything)) {
	&virtual_server::obtain_lock_anything();
	}
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
		&foreign_require("sendmail", "mailers-lib.pl");
		local $mfile = &sendmail::mailers_file(
				&sendmail::get_sendmailcf());
		push(@main::got_lock_virtualmin_mailrelay_files, $mfile);
		}
	if ($config{'domains_file'}) {
		push(@main::got_lock_virtualmin_mailrelay_files,
		     $config{'domains_file'});
		}
	@main::got_lock_virtualmin_mailrelay_files =
		grep { /^\// } @main::got_lock_virtualmin_mailrelay_files;
	foreach my $f (@main::got_lock_virtualmin_mailrelay_files) {
		&lock_file($f);
		}
	}
$mail::got_lock_virtualmin_mailrelay++;
}

# release_lock_virtualmin_mailrelay()
# Unlock whatever files were locked by obtain_lock_virtualmin_mailrelay
sub release_lock_virtualmin_mailrelay
{
if ($main::got_lock_virtualmin_mailrelay == 1) {
	foreach my $f (@main::got_lock_virtualmin_mailrelay_files) {
		&unlock_file($f);
		}
	}
$main::got_lock_virtualmin_mailrelay-- if ($main::got_lock_virtualmin_mailrelay);
if (defined(&virtual_server::release_lock_anything)) {
	&virtual_server::release_lock_anything();
	}
}

# supports_mail_queue()
# Returns 1 if we can list the mail queue on this system
sub supports_mail_queue
{
return $virtual_server::config{'mail_system'} == 0 ||
       $virtual_server::config{'mail_system'} == 1;
}

# list_mail_queue(&domain)
# Returns queued messages for some domain
sub list_mail_queue
{
local ($d) = @_;
local $re = "\@".$d->{'dom'};
if ($virtual_server::config{'mail_system'} == 0) {
	# Get from Postfix
	&foreign_require("postfix");
	local @qfiles = &postfix::list_queue();
	local @rv;
	foreach my $q (@qfiles) {
		if ($q->{'to'} =~ /\Q$re\E/) {
			$q->{'date'} ||= &make_date($q->{'time'});
			push(@rv, $q);
			}
		}
	return @rv;
	}
elsif ($virtual_server::config{'mail_system'} == 1) {
	# Get from Sendmail
	&foreign_require("sendmail");
	local $conf = &sendmail::get_sendmailcf();
	local @qfiles = &sendmail::list_mail_queue($conf);
	local @queue = grep { $_->{'header'}->{'to'} =~ /\Q$re\E/ }
			    map { &sendmail::mail_from_queue($_) } @qfiles;
	local @rv;
	foreach my $q (@queue) {
		push(@rv, { 'from' => $q->{'header'}->{'from'},
			    'to' => $q->{'header'}->{'to'},
			    'subject' => $q->{'header'}->{'subject'},
			    'date' => $q->{'header'}->{'date'},
			    'size' => $q->{'size'} });
		}
	return @rv;
	}
else {
	return ( );
	}
}

1;

