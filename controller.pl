#!/usr/bin/perl
use Mojolicious::Lite;
use Mojo::ByteStream 'b';
use Text::Markdown 'markdown';
use File::Copy 'copy';
app->config(hypnotoad=>{listen => ['http://*:5001']});

my $docdir = './doc/';

sub get_timestamp {
		my $file_name = shift;
		my @modtime = (localtime((stat("$docdir$file_name"))[9]))[5,4,3,2,1,0];
		my $timestr = ((shift @modtime) + 1900) ."/".((shift @modtime) +1) . sprintf("/%02d %02d:%02d:%02d", @modtime[0,1,2,3]);
		return $timestr;
}

sub get_fileinfo {
	my $search = shift;
	my @files = grep { s|$docdir(.+?\.txt)$|$1| } glob("${docdir}*");
	my $fileinfo = {};
	for (@files){
		my $file_name = $_;
		my $word_name = b($file_name)->decode;
		$word_name =~ s/(.+?)\.txt$/$1/;
		my $time = get_timestamp($file_name);
		open my $fh, '<', "$docdir$file_name" or die;
		my $str = '';
		my $ct = 0;
		my $offset = $search == 1 ? 100 : 4;
		while(<$fh>){
		  s/^\s*//;
			s/\n//;
			s/\r//;
			$str .= " $_";
			last if $ct == $offset;
			++$ct;
		}
		$str = b($str)->decode;
		my $laststr = $offset * 20;
		$str = substr($str,0,$laststr);
		$fileinfo->{$word_name}->{time} = $time;
		$fileinfo->{$word_name}->{str} = $str;
	}
	return $fileinfo;
}

sub sorted_fileinfo{
	my $fileinfo = shift;
	my $sort = shift ;
	my $order = shift;
	my @array;
	for my $key (keys(%$fileinfo)) {
		my $hash = {
			time => $fileinfo->{$key}->{time},
			word_name => $key,
		};
		push @array, $hash;
	}
	if ($order eq 'asc' ){
		@array = sort{ $a->{$sort} cmp $b->{$sort} } @array;
	}else{
		@array = sort{ $b->{$sort} cmp $a->{$sort} } @array;
	}
	my @newarray;
	my $n = 0;
	for (@array) {
		my $var = $_;
		my $word_name = $var->{word_name};
		$newarray[$n] = {
			time => $var->{time},
			word_name => $word_name,
			str => $fileinfo->{$word_name}->{str},
		};
		++$n;
	}
	return @newarray;
} 


get '/wordlist' => sub {
	my $self = shift;
	my $sort = $self->req->param('sort') || 'time';
	my $order = $self->req->param('order') || 'dec';
	my $word = $self->req->param('word') || undef;
	return $self->redirect_to('/') unless  $sort =~ /^(time|word_name)$/;
	return $self->redirect_to('/') unless  $order =~ /^(asc|dec)$/;
	my $search = defined $word? 1 : 0;
	my $fileinfo = get_fileinfo($search);
	my @sorted_fileinfo = sorted_fileinfo($fileinfo, $sort, $order);
	if ($word) {
		my $nword = $word;
		my $regex;
		eval {$regex = qr/$nword/i};
		$nword = quotemeta($nword) if $@;
		$regex = qr/$nword/i if $@;
		@sorted_fileinfo = eval {grep { ($_->{word_name} =~ m/$regex/) || ($_->{str} =~ m/$regex/) } @sorted_fileinfo;};
	}

	$self->stash(
		page_title => 'wordlist',
		sorted_fileinfo => \@sorted_fileinfo,
		sort => $sort,
		order => $order,
		word => $word,
	);
} => 'wordlist';

get '/create' => sub {
	my $self = shift;
	my $word_name = $self->flash('word_name'); 
	my $file_name = $self->flash('file_name') || "${word_name}.txt";
	my $textdata = $self->flash('markdown') || 'write here';
	$self->stash( page_title => 'create', file_name => $file_name, textdata => $textdata);
} => 'create';

get '/new'=> sub {
	my $self = shift;
	$self->flash(
		page_title => 'new',
		word_name => 'rename_new',
	);
	$self->redirect_to('create');
};

get '/edit' => sub {
	my $self = shift;
	my $word_name = $self->req->param('word_name');
	my $file_name = "${word_name}.txt";
	my $data_file = "${docdir}${file_name}";

	open my $fh, '<', $data_file;
	my $data = '';
	while (<$fh>) {
		$data .= b($_)->decode;
	}
	$self->stash( page_title => 'edit', file_name => $file_name, textdata => $data );
} => 'create';

post '/search' => sub {
	my $self = shift;
	my $sort = $self->req->param('sort');
	my $order = $self->req->param('order');
	my $word = $self->req->param('word');
	$word = b($word)->encode;
	$word = b($word)->url_escape;
	$self->redirect_to("/wordlist?sort=$sort&order=$order&word=$word");
};

post '/go' => sub {
	my $self = shift;
	my $word_name = $self->req->param('word_name');
	my $current_page = $self->req->param('current_page');
	unless ($word_name ) {
		return $self->redirect_to("/word/$current_page");
	} 
	my $file_name = "${word_name}.txt";
	my $data_file = "${docdir}${file_name}";
	unless ( -e $data_file ) {
		return $self->redirect_to("/word/$current_page");
	} 
	$self->redirect_to("/word/$word_name");
};

post '/post' => sub {
	my $self = shift;
	my $password = $self->param('pass');
	my $file_name = $self->param('file_name');
	my $markdown = $self->param('markdown');

	unless ($password ne '')  {
		$self->flash( file_name => $file_name, markdown => $markdown,);
		return $self->redirect_to('create');
	}

	unless ( -e 'password.txt') {
		open my $fh, '>', 'password.txt';
		print $fh $password;
		close $fh;
	}

	my $savepassword = do('password.txt');

	unless (($password eq $savepassword) and ( $file_name !~ m#(/|\0)#) and ( $file_name =~ m/\.txt$/)) {
		$self->flash( file_name => $file_name, markdown => $markdown,);
		return $self->redirect_to('create');
	}

	my $data_file = "${docdir}${file_name}";
	$file_name =~ s/(.+?)\.txt$/$1/;
	my $word_name = $file_name;
	if ( -e $data_file ){
		copy $data_file , "$docdir${word_name}.old";
	}
	open my $fh, '>', $data_file;
	print $fh $markdown;
	close $fh;
	$self->redirect_to("./word/$word_name");
}; 

get '/' => sub {
	my $self = shift;
	my $data_file = "${docdir}markdown.txt";
	my $time = get_timestamp('markdown.txt');
	open my $fh, '<', $data_file;
	my $data = '';
	while (<$fh>) {
		$data .= b($_)->decode;
	}
	my $html = b(markdown($data))->html_unescape;
	$self->stash(page_title => 'main', word_name => 'markdown', time => $time, html => $html);
} => 'index';


get '/word/:dir' => sub {
	my $self = shift;
	my $word_name = $self->param('dir');
	my $file_name = "${word_name}.txt";
	my $data_file = "${docdir}${file_name}";
	unless ( -e $data_file ) {
		$self->flash(word_name => $word_name,);
		return $self->redirect_to('create');
	} 
	my $time = get_timestamp($file_name);
	open my $fh, '<', $data_file;
	my $data = '';
	while (<$fh>) {
		$data .= b($_)->decode;
	}
	my $html = b(markdown($data))->html_unescape;
	$self->stash( page_title => $word_name, word_name => $word_name, time => $time,  html => $html);
} => 'index';

post 'delete' =>sub {
	my $self = shift;
	my @param = $self->param;
	my @word_names = grep { s/^file-(.+?)$/$1/ } @param;
	my $del = $self->param('del');
	my $password = $self->param('pass');
	my $savepassword = do('password.txt');
	unless (($password eq $savepassword) and ( $del == 1) and @word_names ) {
		return $self->redirect_to('/wordlist');
	}
	for (@word_names ) {
		my $word_name = $_;
		my $data_file = "${docdir}${word_name}.txt";
		if ( -e $data_file ){
			copy $data_file , "$docdir${word_name}.old";
			unlink $data_file;
		}
	}
	$self->redirect_to('/wordlist');
};

get '/:dir'=> sub {
	my $self = shift;
	my $dir = "./word/" . $self->param('dir');
	$self->redirect_to($dir);
};


get '/*/*'=> sub {
	my $self = shift;
	$self->redirect_to('/');
};

app->start;

__DATA__
	
@@ layouts/default.html.ep
<html>
<head>
<meta http-equiv="Content-Type" content="text/html;charset=UTF-8">
<title><%= $page_title %> : MarkdownWiki by @toshi0104</title>
</head>
<body>
<%= content %>
</body>
</html>

@@ index.html.ep
%layout 'default';
<form method='post' action="<%= url_for('/go') %>">
<a href="<%= url_for('/') %>">Main</a> <a href="<%= url_for('/new')%>">New</a>  <a href="<%= url_for("/edit?word_name=$word_name") %>">Edit</a> <a href="<%= url_for('/wordlist') %>">WordList</a>
<input type="text" name="word_name" /><input type='submit' value='GO' /><hr><input type="hidden" name="current_page" value="<%= $word_name %>">
<div id="page_title"><span style="font-size: x-large; font-weigh: bold;"><%= $word_name %></span> date: <%= $time %></div>
<hr>
<%= $html %>

@@ create.html.ep
%layout 'default';
<a href="<%= url_for('/') %>">Main</a>
<hr>
<form method='post' action="<%= url_for('/post') %>">
file name <input type='text' name='file_name' value='<%= $file_name %>' />
password <input type='password' name='pass' /><br />
<hr>
write text by markdown<br />
<textarea name="markdown" rows="30" cols="80"><%=  $textdata  %></textarea><br />
<input type ='submit' value='CREATE' />
</form>

@@ wordlist.html.ep
%layout 'default';
<a href="<%= url_for('/') %>">Main</a><br />
<hr>
<form method='post' action="<%= url_for('/search') %>">
Time ( <a href="<%= url_for('/wordlist?sort=time&order=asc') %>">asc</a> | <a href="<%= url_for('/wordlist?sort=time&order=dec') %>">dec</a> )
WordName ( <a href="<%= url_for('/wordlist?sort=word_name&order=asc') %>">asc</a> | <a href="<%= url_for('/wordlist?sort=word_name&order=dec') %>">dec</a> )
<input type='text' name='word' value="<%= $word %>" /><input type='hidden' name='sort' value="<%= $sort %>"/><input type='hidden' name='order' value="<%= $order %>"/><input type ='submit' value='SEARCH' /></form>
<hr>
<form method='post' action="<%= url_for('/delete') %>">
<input type="checkbox" name="del" value="1"/> Check to delete.     Password <input type="password" name="pass" /><input type='submit' value='DELTE' /><br /><hr>
<% for ( @$sorted_fileinfo) { %>
<%= $_->{time} %> <input type="checkbox" name="file-<%= $_->{word_name}%>" value='1' /> <a href="<%= url_for("/word/$_->{word_name}") %>"><%= $_->{word_name} %></a> : <%= $_->{str} %><br />
<% } %>
</form> 





