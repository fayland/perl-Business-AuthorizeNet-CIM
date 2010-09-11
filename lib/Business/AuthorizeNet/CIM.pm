package Business::AuthorizeNet::CIM;

# ABSTRACT: Authorize.Net CIM

use Carp qw/croak/;
use LWP::UserAgent;
use XML::Writer;
use XML::Simple 'XMLin';

=head1 SYNOPSIS
 
    use Business::AuthorizeNet::CIM;
    use Data::Dumper;
    
    my $cim = Business::AuthorizeNet::CIM->new( login => $cfg{login}, transactionKey => $cfg{password} );
    my $d = $cim->getCustomerProfileIds();
    my $id_num = $d->{ids}->{numericString};
    my @ids = ref($id_num) eq 'ARRAY' ? @$id_num : ($id_num);
    foreach my $id (@ids) {
        my $d = $cim->getCustomerProfile($id);
        print Dumper(\$d);
    }

=head1 DESCRIPTION

BETA. NOT FINISHED. Sample code for L<http://developer.authorize.net/api/cim/>

=head2 METHODS

=head3 CONSTRUCTION

    my $cim = Business::AuthorizeNet::CIM->new(
        login => $cfg{login},
        transactionKey => $cfg{password}
    );

=over 4

=item * login

=item * transactionKey

you get them from L<http://developer.authorize.net/>

=item * debug

=item * test_mode

validationMode as testMode or liveMode

=item * ua_args

passed to LWP::UserAgent

=item * ua

L<LWP::UserAgent> or L<WWW::Mechanize> instance

=back

=cut

sub new {
    my $class = shift;
    my $args = scalar @_ % 2 ? shift : { @_ };
    
    # validate
    $args->{login} or croak 'login is required';
    $args->{transactionKey} or croak 'transactionKey is required';
    
    if ($args->{test_mode}) {
        $args->{url} = 'https://apitest.authorize.net/xml/v1/request.api';
    } else {
        $args->{url} = 'https://api.authorize.net/xml/v1/request.api';
    }

    unless ( $args->{ua} ) {
        my $ua_args = delete $args->{ua_args} || {};
        $args->{ua} = LWP::UserAgent->new(%$ua_args);
    }

    bless $args, $class;
}

=pod

=head3 createCustomerProfile

    $cim->createCustomerProfile(
        merchantCustomerId => $merchantCustomerId,
        description => $description,
        email => $email,
        cardNumber => $cardNumber,
        expirationDate => $expirationDate,
        cardCode => $cardCode,
        # shipToList
        # 'firstName', 'lastName', 'company', 'address', 'city', 'state', 'zip', 'country', 'phoneNumber', 'faxNumber'
        firstName => $firstName,
        lastName  => $lastName,
    );

=cut

sub createCustomerProfile {
    my $self = shift;
    my $args = scalar @_ % 2 ? shift : { @_ };

    my $xml;
    my $writer = XML::Writer->new(OUTPUT => \$xml);
    $writer->startTag('createCustomerProfileRequest', 'xmlns' => 'AnetApi/xml/v1/schema/AnetApiSchema.xsd');
    $writer->startTag('merchantAuthentication');
    $writer->dataElement('name', $self->{login});
    $writer->dataElement('transactionKey', $self->{transactionKey});
    $writer->endTag('merchantAuthentication');
    $writer->startTag('profile');
    foreach my $k ('merchantCustomerId', 'description', 'email') {
        $writer->dataElement($k, $args->{$k})
            if exists $args->{$k};
    }
    $writer->dataElement('email', $args->{email});
    $writer->startTag('paymentProfiles');
    $writer->dataElement('customerType', $args->{'customerType'}) if exists $args->{'customerType'};
    $writer->startTag('payment');
    $writer->startTag('creditCard');
    $writer->dataElement('cardNumber', $args->{cardNumber});
    $writer->dataElement('expirationDate', $args->{expirationDate});
    $writer->dataElement('cardCode', $args->{cardCode});
    $writer->endTag('creditCard');
    $writer->endTag('payment');
    $writer->endTag('paymentProfiles');
    my @flds = ('firstName', 'lastName', 'company', 'address', 'city', 'state', 'zip', 'country', 'phoneNumber', 'faxNumber');
    if (grep { $args->{$_} } @flds) {
        $writer->startTag('shipToList');
        foreach my $k (@flds) {
            $writer->dataElement($k, $args->{$k})
                if exists $args->{$k};
        }
        $writer->endTag('shipToList');
    }
    $writer->endTag('profile');
    if ($self->{test_mode}) {
        $writer->dataElement('validationMode', 'testMode');
    }
    $writer->endTag('createCustomerProfileRequest');

    $xml = '<?xml version="1.0" encoding="utf-8"?>' . "\n" . $xml;
    my $resp = $self->{ua}->post($self->{url}, Content => $xml, 'Content-Type' => 'text/xml');

    my $d = XMLin($resp->content);
    
    print "<!-- $xml -->\n\n" if $self->{debug};
    if ($d->{messages}->{resultCode} eq 'Error') {
        return {
            resultCode => 'Error',
            %{$d->{messages}->{message}},
        }
    } else {
        return {
            resultCode => 'Ok',
            %$d
        };
    }
}

=pod

=head3 getCustomerProfileIds

    $cim->getCustomerProfileIds;

=cut

sub getCustomerProfileIds {
    my $self = shift;

    my $xml;
    my $writer = XML::Writer->new(OUTPUT => \$xml);
    $writer->startTag('getCustomerProfileIdsRequest', 'xmlns' => 'AnetApi/xml/v1/schema/AnetApiSchema.xsd');
    $writer->startTag('merchantAuthentication');
    $writer->dataElement('name', $self->{login});
    $writer->dataElement('transactionKey', $self->{transactionKey});
    $writer->endTag('merchantAuthentication');
    if ($self->{test_mode}) {
        $writer->dataElement('validationMode', 'testMode');
    }
    $writer->endTag('getCustomerProfileIdsRequest');

    $xml = '<?xml version="1.0" encoding="utf-8"?>' . "\n" . $xml;
    my $resp = $self->{ua}->post($self->{url}, Content => $xml, 'Content-Type' => 'text/xml');

    my $d = XMLin($resp->content);
    
    print "<!-- $xml -->\n\n" if $self->{debug};
    return $d;
}

=pod

=head3 getCustomerProfile

    $cim->getCustomerProfile($customerProfileId);

=cut

sub getCustomerProfile {
    my ($self, $customerProfileId) = @_;
    
    my $xml;
    my $writer = XML::Writer->new(OUTPUT => \$xml);
    $writer->startTag('getCustomerProfileRequest', 'xmlns' => 'AnetApi/xml/v1/schema/AnetApiSchema.xsd');
    $writer->startTag('merchantAuthentication');
    $writer->dataElement('name', $self->{login});
    $writer->dataElement('transactionKey', $self->{transactionKey});
    $writer->endTag('merchantAuthentication');
    $writer->dataElement('customerProfileId', $customerProfileId);
    if ($self->{test_mode}) {
        $writer->dataElement('validationMode', 'testMode');
    }
    $writer->endTag('getCustomerProfileRequest');

    $xml = '<?xml version="1.0" encoding="utf-8"?>' . "\n" . $xml;
    my $resp = $self->{ua}->post($self->{url}, Content => $xml, 'Content-Type' => 'text/xml');

    my $d = XMLin($resp->content);
    
    print "<!-- $xml -->\n\n" if $self->{debug};
    return $d;
}

=pod

=head3 deleteCustomerProfile

    $cim->deleteCustomerProfile($customerProfileId);

=cut

sub deleteCustomerProfile {
    my ($self, $customerProfileId) = @_;
    
    my $xml;
    my $writer = XML::Writer->new(OUTPUT => \$xml);
    $writer->startTag('deleteCustomerProfileRequest', 'xmlns' => 'AnetApi/xml/v1/schema/AnetApiSchema.xsd');
    $writer->startTag('merchantAuthentication');
    $writer->dataElement('name', $self->{login});
    $writer->dataElement('transactionKey', $self->{transactionKey});
    $writer->endTag('merchantAuthentication');
    $writer->dataElement('customerProfileId', $customerProfileId);
    if ($self->{test_mode}) {
        $writer->dataElement('validationMode', 'testMode');
    }
    $writer->endTag('deleteCustomerProfileRequest');

    $xml = '<?xml version="1.0" encoding="utf-8"?>' . "\n" . $xml;
    my $resp = $self->{ua}->post($self->{url}, Content => $xml, 'Content-Type' => 'text/xml');

    my $d = XMLin($resp->content);
    
    print "<!-- $xml -->\n\n" if $self->{debug};
    return $d;
}

=pod

=head3 validateCustomerPaymentProfile

    $cim->validateCustomerPaymentProfile(
        customerProfileId => $customerProfileId,
        customerPaymentProfileId => $customerPaymentProfileId,
        customerShippingAddressId => $customerShippingAddressId,
    );

=cut

sub validateCustomerPaymentProfile {
    my $self = shift;
    my $args = scalar @_ % 2 ? shift : { @_ };
    
    my $xml;
    my $writer = XML::Writer->new(OUTPUT => \$xml);
    $writer->startTag('validateCustomerPaymentProfileRequest', 'xmlns' => 'AnetApi/xml/v1/schema/AnetApiSchema.xsd');
    $writer->startTag('merchantAuthentication');
    $writer->dataElement('name', $self->{login});
    $writer->dataElement('transactionKey', $self->{transactionKey});
    $writer->endTag('merchantAuthentication');
    $writer->dataElement('customerProfileId', $args->{customerProfileId});
    $writer->dataElement('customerPaymentProfileId', $args->{customerPaymentProfileId});
    $writer->dataElement('customerShippingAddressId', $args->{customerShippingAddressId})
        if $args->{customerShippingAddressId};
    $writer->dataElement('cardCode', $args->{cardCode}) if $args->{cardCode};
    if ($self->{test_mode}) {
        $writer->dataElement('validationMode', 'testMode');
    } else {
        $writer->dataElement('validationMode', 'liveMode');
    }
    $writer->endTag('validateCustomerPaymentProfileRequest');

    $xml = '<?xml version="1.0" encoding="utf-8"?>' . "\n" . $xml;
    my $resp = $self->{ua}->post($self->{url}, Content => $xml, 'Content-Type' => 'text/xml');

    my $d = XMLin($resp->content);
    
    print "<!-- $xml -->\n\n" if $self->{debug};
    return $d;
}

=pod

=head3 createCustomerProfileTransaction

    $cim->createCustomerProfileTransaction(
        'profileTransAuthCapture', # or others like profileTransAuthOnly
        customerProfileId => $customerProfileId,
        customerPaymentProfileId => $customerPaymentProfileId,
        customerShippingAddressId => $customerShippingAddressId,
        recurringBilling => 'true'
    );

=cut

sub createCustomerProfileTransaction {
    my $self = shift;
    my $type = shift;
    my $args = scalar @_ % 2 ? shift : { @_ };
    
    my $xml;
    my $writer = XML::Writer->new(OUTPUT => \$xml);
    $writer->startTag('createCustomerProfileTransactionRequest', 'xmlns' => 'AnetApi/xml/v1/schema/AnetApiSchema.xsd');
    $writer->startTag('merchantAuthentication');
    $writer->dataElement('name', $self->{login});
    $writer->dataElement('transactionKey', $self->{transactionKey});
    $writer->endTag('merchantAuthentication');
    $writer->startTag('transaction');
    $writer->startTag($type); # profileTransAuthOnly, profileTransPriorAuthCapture
    $writer->dataElement('amount', $args->{amount});
    $writer->dataElement('customerProfileId', $args->{customerProfileId});
    $writer->dataElement('customerPaymentProfileId', $args->{customerPaymentProfileId});
    $writer->dataElement('customerShippingAddressId', $args->{customerShippingAddressId})
        if $args->{customerShippingAddressId};
    $writer->dataElement('recurringBilling', $args->{recurringBilling})
        if $args->{recurringBilling};
    $writer->dataElement('cardCode', $args->{cardCode}) if $args->{cardCode};
    $writer->endTag($type);
    $writer->endTag('transaction');
    $writer->endTag('createCustomerProfileTransactionRequest');

    $xml = '<?xml version="1.0" encoding="utf-8"?>' . "\n" . $xml;
    my $resp = $self->{ua}->post($self->{url}, Content => $xml, 'Content-Type' => 'text/xml');

    my $d = XMLin($resp->content);
    
    print "<!-- $xml -->\n\n" if $self->{debug};
    return $d;
}

=pod

=head3 updateCustomerProfile

    $cim->updateCustomerProfile(
        customerProfileId => $customerProfileId,
        merchantCustomerId => $merchantCustomerId,
        description => $description,
        email => $email
    );

=cut

sub updateCustomerProfile {
    my $self = shift;
    my $args = scalar @_ % 2 ? shift : { @_ };
    
    my $xml;
    my $writer = XML::Writer->new(OUTPUT => \$xml);
    $writer->startTag('updateCustomerProfileRequest', 'xmlns' => 'AnetApi/xml/v1/schema/AnetApiSchema.xsd');
    $writer->startTag('merchantAuthentication');
    $writer->dataElement('name', $self->{login});
    $writer->dataElement('transactionKey', $self->{transactionKey});
    $writer->endTag('merchantAuthentication');
    $writer->startTag('profile');
    foreach my $k ('merchantCustomerId', 'description', 'email') {
        $writer->dataElement($k, $args->{$k})
            if exists $args->{$k};
    }
    $writer->dataElement('customerProfileId', $args->{customerProfileId});
    $writer->endTag('profile');
    $writer->endTag('updateCustomerProfileRequest');

    $xml = '<?xml version="1.0" encoding="utf-8"?>' . "\n" . $xml;
    my $resp = $self->{ua}->post($self->{url}, Content => $xml, 'Content-Type' => 'text/xml');

    my $d = XMLin($resp->content);
    
    print "<!-- $xml -->\n\n" if $self->{debug};
    return $d;
}

=pod

=head3 updateCustomerPaymentProfile

    $cim->updateCustomerProfile(
        customerProfileId => $customerProfileId,
        customerPaymentProfileId => $customerPaymentProfileId,
        cardNumber => $cardNumber,
        expirationDate => $expirationDate,
        cardCode => $cardCode
    );

=cut

sub updateCustomerPaymentProfile {
    my $self = shift;
    my $args = scalar @_ % 2 ? shift : { @_ };
    
    my $xml;
    my $writer = XML::Writer->new(OUTPUT => \$xml);
    $writer->startTag('updateCustomerPaymentProfileRequest', 'xmlns' => 'AnetApi/xml/v1/schema/AnetApiSchema.xsd');
    $writer->startTag('merchantAuthentication');
    $writer->dataElement('name', $self->{login});
    $writer->dataElement('transactionKey', $self->{transactionKey});
    $writer->endTag('merchantAuthentication');
    $writer->dataElement('customerProfileId', $args->{customerProfileId});
    $writer->startTag('paymentProfile');
    $writer->dataElement('customerType', $args->{'customerType'}) if exists $args->{'customerType'};
    $writer->startTag('payment');
    $writer->startTag('creditCard');
    $writer->dataElement('cardNumber', $args->{cardNumber});
    $writer->dataElement('expirationDate', $args->{expirationDate});
    $writer->dataElement('cardCode', $args->{cardCode});
    $writer->endTag('creditCard');
    $writer->endTag('payment');
    $writer->dataElement('customerPaymentProfileId', $args->{customerPaymentProfileId});
    $writer->endTag('paymentProfile');
    $writer->endTag('updateCustomerPaymentProfileRequest');

    $xml = '<?xml version="1.0" encoding="utf-8"?>' . "\n" . $xml;
    my $resp = $self->{ua}->post($self->{url}, Content => $xml, 'Content-Type' => 'text/xml');

    my $d = XMLin($resp->content);
    
    print "<!-- $xml -->\n\n" if $self->{debug};
    return $d;
}

=pod

=head3 updateCustomerShippingAddress

    $cim->updateCustomerShippingAddress(
        customerProfileId => $customerProfileId,
        customerAddressId => $customerAddressId,
        # firstName', 'lastName', 'company', 'address', 'city', 'state', 'zip', 'country', 'phoneNumber', 'faxNumber'
        firstName => $firstName,
        lastName => $lastName,
        company => $company
    );

=cut

sub updateCustomerShippingAddress {
    my $self = shift;
    my $args = scalar @_ % 2 ? shift : { @_ };
    
    my $xml;
    my $writer = XML::Writer->new(OUTPUT => \$xml);
    $writer->startTag('updateCustomerShippingAddressRequest', 'xmlns' => 'AnetApi/xml/v1/schema/AnetApiSchema.xsd');
    $writer->startTag('merchantAuthentication');
    $writer->dataElement('name', $self->{login});
    $writer->dataElement('transactionKey', $self->{transactionKey});
    $writer->endTag('merchantAuthentication');
    $writer->dataElement('customerProfileId', $args->{customerProfileId});
    $writer->startTag('address');
    my @flds = ('firstName', 'lastName', 'company', 'address', 'city', 'state', 'zip', 'country', 'phoneNumber', 'faxNumber');
    foreach my $k (@flds) {
        $writer->dataElement($k, $args->{$k})
            if exists $args->{$k};
    }
    $writer->dataElement('customerAddressId', $args->{customerAddressId});
    $writer->endTag('address');
    $writer->endTag('updateCustomerShippingAddressRequest');

    $xml = '<?xml version="1.0" encoding="utf-8"?>' . "\n" . $xml;
    my $resp = $self->{ua}->post($self->{url}, Content => $xml, 'Content-Type' => 'text/xml');

    my $d = XMLin($resp->content);
    
    print "<!-- $xml -->\n\n" if $self->{debug};
    return $d;
}

1;