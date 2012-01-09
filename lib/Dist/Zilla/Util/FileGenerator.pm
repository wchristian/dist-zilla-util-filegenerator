use strictures;

package Dist::Zilla::Util::FileGenerator;

# VERSION

# ABSTRACT: helper to generate files with little repetition in a PluginBundle

# COPYRIGHT

use Moose;
use MooseX::HasDefaults::RO;

sub {
    has $_ => ( required => 1 ) for qw( files source );

    has generators_added => ( is => 'rw' );

    has move                   => ( default => 0 );
    has is_template            => ( default => 1 );
    has source_type            => ( default => 'module' );
    has generate_before_plugin => ( default => 'Manifest' );
    has exclusion_keys         => ( default => sub { { GatherDir => 'exclude_filename', PruneCruft => 'except' } } );

    has prepared_files => ( lazy => 1, builder => "_build_prepared_files" );
  }
  ->();

=head1 METHODS

=head2 combine_with

    my @plugins_with_generated_files = $gen->combine_with( @plain_plugins );

Given an array containing specs for a plugin bundle this method returns an array
with the necessary exclusions, generators and copiers added.

=cut

sub combine_with {
    my ( $self, @plugins ) = @_;

    $self->generators_added( 0 );

    @plugins = map $self->_add_file_exclusions( $_ ),    @plugins;
    @plugins = map $self->_add_generators_copiers( $_ ), @plugins;

    die "could not find the plugin before which generators should be inserted" if !$self->generators_added;
    $self->generators_added( 0 );

    return @plugins;
}

sub _add_file_exclusions {
    my ( $self, $entry ) = @_;

    my ( $plugin, $name, $config ) = $self->_parse_plugin_entry( $entry );

    if ( my $key = $self->exclusion_keys->{$plugin} ) {
        $config->{$key} ||= [];
        $config->{$key} = [ $config->{$key} ] if !ref $config->{$key};
        push @{ $config->{$key} }, $self->file_names;

        return $self->_build_plugin_entry( $plugin, $name, $config );
    }

    return $entry;
}

sub _add_generators_copiers {
    my ( $self, $entry ) = @_;

    my ( $plugin, $name, $config ) = $self->_parse_plugin_entry( $entry );

    return $entry if $plugin ne $self->generate_before_plugin;

    $self->generators_added( 1 );

    return ( $self->generators, $self->copiers, $entry );
}

sub _parse_plugin_entry {
    my ( $self, $entry ) = @_;

    return ( $entry, undef, {} ) if !ref $entry;

    my @spec = @{$entry};
    return ( $spec[0], undef, {} ) if @spec == 1;
    return ( $spec[0], $spec[1], {} ) if @spec == 2 and !ref $spec[1];
    return ( $spec[0], undef, $spec[1] ) if @spec == 2 and ref $spec[1];
    return ( $spec[0], $spec[1], $spec[2] ) if @spec == 3;

    die "weird plugin spec: @spec";
}

sub _build_plugin_entry {
    my ( $self, $plugin, $name, $config ) = @_;

    my @entry = ( $plugin );
    push @entry, $name if $name;
    push @entry, $config;

    return \@entry;
}

sub _build_prepared_files {
    my ( $self ) = @_;
    return [ map $self->_prepare_file( $_ ), @{ $self->files } ];
}

sub _prepare_file {
    my ( $self, $file ) = @_;

    my %file = ( name => $file );
    %file = ( name => shift @{$file}, @{$file} ) if ref $file;

    for my $key ( qw( move source_type source is_template ) ) {
        $file{$key} = $self->$key if !exists $file{$key};
    }

    return \%file;
}

=head2 generators

    my @generator_plugins = $gen->generators;

Returns an array with the necessary generators for inclusion in a plugin bundle.

=cut

sub generators {
    my ( $self ) = @_;

    return map $self->_file_generator( $_ ), @{ $self->prepared_files };
}

=head2 file_names

    my @generated_files = $gen->file_names;

Returns an array with the file names of the generated files.

=cut

sub file_names {
    my ( $self ) = @_;
    return map $_->{name}, @{ $self->prepared_files };
}

=head2 copiers

    my @generated_files = $gen->copiers;

Returns an array with the necessary copiers for inclusion in a plugin bundle.

=cut

sub copiers {
    my ( $self ) = @_;
    return map $self->_file_copier( $_ ), @{ $self->prepared_files };
}

sub _file_generator {
    my ( $self, $file ) = @_;

    my $content;
    $content = $self->_module_template( $file->{source}, $file->{name} ) if $file->{source_type} eq 'module';
    $content .= $file->{extra_content} if $file->{extra_content};

    my $generator = [
        GenerateFile => "Generate-$file->{name}" => {
            filename    => $file->{name},
            is_template => $file->{is_template},
            content     => $content,
        }
    ];

    return $generator;
}

sub _module_template {
    my ( $self, $class, $file_name ) = @_;
    return $class->data( $file_name );
}

sub _file_copier {
    my ( $self, $file ) = @_;

    my $op = $file->{move} ? "move" : "copy";

    return [ CopyFilesFromBuild => "Copy-$file->{name}" => { $op => $file->{name} } ];
}

1;
