use strict;
use lib '/export/home/sybase/clients-mssql/current64/perl';
use DBI;
use Getopt::Std;


sub SubstituteParams($$)
{
  my $template = shift;
  my $params = shift;

  foreach my $s (keys %$params) {
    #my $re = qr{/%$s%/};
    $template =~ s/%$s%/$$params{$s}/gex;
    #if ($template =~ $re) {
     # $template =~ $` . $$params{$s} . $';
    #}
  }
  return $template;
}

sub Dump
{
  my $dbh = shift;
  my $sql = shift;
  my $output_dir = shift;
  my $template_dir = shift;
  my @object_names = @_;

  if (@object_names) {
    $sql .= " and o.name in ('" . join("', '", @object_names) . "')";
  }
  # Prepare the statement.
  my $sth = $dbh->prepare($sql)
      or die "Can't prepare statement: $DBI::errstr";

  # Execute the statement.
  $sth->execute();

  my %ext = (
    "P" => "prc", 
    "PC" => "prc", 
    "FN" => "udf", 
    "FS" => "udf", 
    "TF" => "udf", 
    "V" => "viw", 
    "TR" => "trg", 
    "IF" => "udf"
  );

  # Fetch and display the result set value.
  while (my @row = $sth->fetchrow_array) {
    $row[1] =~ s/\s+//;
    $row[2] =~ s/^\s*//s;
    $row[2] =~ s|/\*\s+\$Id.+?\*/\s*$||si;
    $row[2] =~ s/\s*$//s;

    my $fn;
    if (-e "$template_dir/object-update.$row[1].$ext{$row[1]}") {
      $fn = "$template_dir/object-update.$row[1].$ext{$row[1]}";
    } else {
      $fn = "$template_dir/object-update.$ext{$row[1]}";
    }
    open TMPL, "<$fn" or die "Can't open template file $fn";
    my $x = $/;
    undef $/;
    my $template = <TMPL>;
    $/ = $x;
    close TMPL;

    my $alter_create = 'ALTER';
    $alter_create = 'CREATE' if $template =~ /drop/is;

    if ($row[2] =~ /^\s*CREATE\s+(\w+)\s+(?:\[?dbo\]?\.)?\[?([^\]\n\(]+)\]?/si) {
      my $a = $1;
      my $b = $2;
      my $c = $';
      if ($a =~ /^proc/i) {
        $row[2] = "$alter_create PROCEDURE dbo.$b$c";
      } elsif ($a =~ /^func/i) {
        $row[2] = "$alter_create FUNCTION dbo.$b$c";
      } elsif ($a =~ /^trigger/i) {
        $row[2] = "$alter_create TRIGGER dbo.$b$c";
      } else {
        $row[2] = "$alter_create $a dbo.$b$c";
      }
    }

    my %params = ();
    $params{"object_ddl"} = $row[2];
    $params{"object_name"} = $row[0];

    $template = SubstituteParams($template, \%params);

    unless (-d "$output_dir"){
      mkdir "$output_dir" or die;
    }
    open SQL, ">$output_dir$row[0]\.$ext{$row[1]}" or die $!;
    $template =~ s/\r\n/\n/gs;
    print SQL $template;
    close SQL;
  }
}

$Getopt::Std::STANDARD_HELP_VERSION = 1;
$Getopt::Std::OUTPUT_HELP_VERSION = 1;

my %opts;
getopts('s:d:u:p:o:t:', \%opts);

my $server = $opts{'s'};
my $database = $opts{'d'};
my $user = $opts{'u'};
my $password = $opts{'p'};
my $output_dir = $opts{'o'} ? $opts{'o'} : '.';
my $template_dir = $opts{'t'};
my @object_names = @ARGV;

if (!$password && $user) {
  $password = $user . "_pw";
}

unless ($server || $database || $user || $password || $template_dir) {
  print STDERR "usage: dump_ddl -s <server> -d <database> -u <user> -p <password> -t <templates dir> [-o <output directory> <object names>]\n";
  exit(1);
}

my %attr = (
    PrintError => 0,
    RaiseError => 0
);

my $data_source_unix = "dbi:Sybase:$server";
my $data_source_windows = "dbi:ODBC:$server";

if ($output_dir && $output_dir !~ /\/$/) {
  $output_dir = "$output_dir/";
}

# Connect to the data source and get a handle for that connection.
my $dbh;

#($dbh = DBI->connect($data_source_windows, $user, $password, \%attr))
#    or 
($dbh = DBI->connect($data_source_unix, $user, $password, \%attr))
    or die "Can't connect to $data_source_unix: $DBI::errstr";

#$dbh->{LongReadLen} = 100000;
$dbh->{PrintError} = 1;

$dbh->do("use $database;");
$dbh->do("set textsize 50000000");

my $sql = "select name, type, definition from sys.objects o, sys.sql_modules m where o.is_ms_shipped = 0 and o.object_id = m.object_id and definition is not null and name not like '%diagram%'";

Dump($dbh, $sql, $output_dir, $template_dir, @object_names);

$sql = qq(
select o.name name, type, 'CREATE ' + case when type='FS' then 'FUNCTION' else 'PROCEDURE' end + ' dbo.' + o.name + 
       case when p1.definition is not null and type = 'FS' then '(' else '' end +
       %params%
       case when p1.definition is not null and type = 'FS' then ')' else '' end +
       case when ret.definition is not null then char(10) + 'RETURNS ' + ret.definition + ' ' else char(10) end + 'WITH EXECUTE AS CALLER ' + char(10) + 
       char(10) + 'AS' + char(10) + 'EXTERNAL NAME ' + '[' + a.name + '].[' + assembly_class + '].[' + assembly_method + ']' definition
  from sys.objects o 
        join sys.assembly_modules am on o.object_id = am.object_id 
        join sys.assemblies a on am.assembly_id = a.assembly_id
        left join 
             (select object_id, p.name + ' [' + t.name + 
                     case when t.name like '%char%' or t.name = 'varbinary' 
                          then '](' + case when p.max_length > 0 
                                          then convert(varchar, p.max_length/2) 
                                          else 'max' end + 
                               ')' 
                          else ']' 
                     end definition, ' ' is_func
               from sys.parameters p 
                      join sys.types t on p.system_type_id = t.system_type_id and p.user_type_id = t.user_type_id
              where p.name = ''
             )  ret on ret.object_id = o.object_id
);

my $params = '';
for(my $i = 1; $i <= 20; ++$i) {
  $sql = $sql . sprintf (qq(left join (select object_id, p.name + ' [' + t.name + 
                     case when t.name like '%%char%%' or t.name = 'varbinary' 
                          then '](' + case when p.max_length > 0 
                                          then convert(varchar, p.max_length/2) 
                                          else 'max' end + 
                               ')' 
                          else ']' 
                     end + 
                     case when is_output = 1 
                          then ' output'
                          else ''
                     end definition
               from sys.parameters p 
                      join sys.types t on p.system_type_id = t.system_type_id and p.user_type_id = t.user_type_id
              where parameter_id = %d
             )  p%d on p%d.object_id = o.object_id
          ), $i, $i, $i);

  if ($i == 1) {
    $params = $params . sprintf(qq(case when p%d.definition is not null then isnull(ltrim(is_func), char(10)) + p%d.definition else '' end +), $i, $i);  
  } else {
    $params = $params . sprintf(qq(case when p%d.definition is not null then ',' + isnull(is_func, char(10)) + p%d.definition else '' end +), $i, $i);  
  }
}

$sql =~ s/%params%/$params/s;
$sql = $sql . ' where 1=1 ';

Dump($dbh, $sql, $output_dir, $template_dir, @object_names);

# Disconnect the database from the database handle.
$dbh->disconnect;

