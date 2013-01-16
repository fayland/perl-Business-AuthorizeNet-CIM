package Business::AuthorizeNet::CIM;

# ABSTRACT: Authorize.Net Customer Information Manager (CIM) Web Services API

use strict;
use warnings;
use Carp qw/croak/;
use LWP::UserAgent;
use XML::Writer;
use XML::Simple 'XMLin';

=head1 SYNOPSIS

    use Business::AuthorizeNet::CIM;
    use Data::Dumper;

    my $cim = Business::AuthorizeNet::CIM->new( login => $cfg{login}, transactionKey => $cfg{password} );

    my @ProfileIds = $cim->getCustomerProfileIds();
    foreach my $id (@ProfileIds) {
        my $d = $cim->getCustomerProfile($id);
        print Dumper(\$d);
    }

=head1 DESCRIPTION

Authorize.Net Customer Information Manager (CIM) Web Services API for L<http://developer.authorize.net/api/cim/>, read L<http://www.authorize.net/support/CIM_XML_guide.pdf> for more details.

=head2 METHODS

=head3 CONSTRUCTION

    my $cim = Business::AuthorizeNet::CIM->new(
        login => $cfg{login},
        transactionKey => $cfg{password}
    );

=over 4

=item * login

The valid API Login ID for the developer test or merchant account

=item * transactionKey

The valid Transaction Key for the developer test or merchant account

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

Create a new customer profile along with any customer payment profiles and
customer shipping addresses for the customer profile.

    $cim->createCustomerProfile(
        refId => $refId, # Optional

        # one of 'merchantCustomerId', 'description', 'email' is required
        merchantCustomerId => $merchantCustomerId,
        description => $description,
        email => $email,

        customerType => $customerType, # Optional

        billTo => { # Optional, all sub items are Optional
            firstName => $firstName,
            lastName  => $lastName,
            company   => $company,
            address   => $address,
            city      => $city,
            state     => $state,
            zip       => $zip,
            country   => $country,
            phoneNumber => $phoneNumber,
            faxNumber => $faxNumber
        },

        # or it uses shipToList address as billTo
        use_shipToList_as_billTo => 1,

        creditCard => { # required when the payment profile is credit card
            cardNumber => $cardNumber,
            expirationDate => $expirationDate, # YYYY-MM
            cardCode => $cardCode,  # Optional
        },

        bankAccount => { # required when the payment profile is bank account
            accountType => $accountType, # Optional, one of checking, savings, businessChecking
            routingNumber => $routingNumber,
            accountNumber => $accountNumber,
            nameOnAccount => $nameOnAccount,
            echeckType => $echeckType, # Optionaal, one of CCD, PPD, TEL, WEB
            bankName   => $bankName, # Optional
        },

        shipToList => {
            firstName => $firstName,
            lastName  => $lastName,
            company   => $company,
            address   => $address,
            city      => $city,
            state     => $state,
            zip       => $zip,
            country   => $country,
            phoneNumber => $phoneNumber,
            faxNumber => $faxNumber
        },

        # or it uses billTo address as shipToList
        use_billTo_as_shipToList => 1,

    );

=cut

sub _need_payment_profiles_section {
    my ($self, $args) = @_;
    return exists $args->{billTo}
        || exists $args->{creditCard}
        || exists $args->{bankAccount}
        || ( $args->{use_shipToList_as_billTo} and $args->{shipToList} );
}

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
    $writer->dataElement('refId', $args->{refId}) if exists $args->{refId};
    $writer->startTag('profile');
    foreach my $k ('merchantCustomerId', 'description', 'email') {
        $writer->dataElement($k, $args->{$k})
            if exists $args->{$k};
    }

    my @flds = qw(
      firstName lastName company address city state zip country
      phoneNumber faxNumber
    );

    my $need_payment_profiles = $self->_need_payment_profiles_section($args);
    if ($need_payment_profiles) {
        $writer->startTag('paymentProfiles');
        $writer->dataElement('customerType', $args->{'customerType'}) if exists $args->{'customerType'};

        if (exists $args->{billTo} or ( $args->{use_shipToList_as_billTo} and $args->{shipToList} )) {
            my $addr = exists $args->{billTo} ? $args->{billTo} : $args->{shipToList};
            $writer->startTag('billTo');
            foreach my $k (@flds) {
                $writer->dataElement($k, $addr->{$k})
                    if exists $addr->{$k};
            }
            $writer->endTag('billTo');
        }

        $writer->startTag('payment');

        if (exists $args->{creditCard}) {
            $writer->startTag('creditCard');
            foreach my $k ('cardNumber', 'expirationDate', 'cardCode') {
                $writer->dataElement($k, $args->{creditCard}->{$k})
                    if exists $args->{creditCard}->{$k};
            }
            $writer->endTag('creditCard');
        }
        if (exists $args->{bankAccount}) {
            $writer->startTag('bankAccount');
            foreach my $k ('accountType', 'routingNumber', 'accountNumber', 'nameOnAccount', 'echeckType', 'bankName') {
                $writer->dataElement($k, $args->{bankAccount}->{$k});
            }
            $writer->endTag('bankAccount');
        }

        $writer->endTag('payment');
        $writer->endTag('paymentProfiles');
    }

    if (exists $args->{shipToList} or ( $args->{use_billTo_as_shipToList} and $args->{billTo} )) {
        my $addr = exists $args->{shipToList} ? $args->{shipToList} : $args->{billTo};
        $writer->startTag('shipToList');
        foreach my $k (@flds) {
            $writer->dataElement($k, $addr->{$k})
                if exists $addr->{$k};
        }
        $writer->endTag('shipToList');
    }

    $writer->endTag('profile');
    if ($need_payment_profiles && $self->{test_mode}) {
        $writer->dataElement('validationMode', 'testMode');
    }
    $writer->endTag('createCustomerProfileRequest');

    $xml = '<?xml version="1.0" encoding="utf-8"?>' . "\n" . $xml;
    print "<!-- $xml -->\n\n" if $self->{debug};
    my $resp = $self->{ua}->post($self->{url}, Content => $xml, 'Content-Type' => 'text/xml');
    print "<!-- " . $resp->content . " -->\n\n" if $self->{debug};

    my $d = XMLin($resp->content, SuppressEmpty => '');
    return $d;
}

=pod

=head3 createCustomerPaymentProfileRequest

Create a new customer payment profile for an existing customer profile. You can create up to 10 payment profiles for each customer profile.

    $cim->createCustomerPaymentProfileRequest(
        customerProfileId => $customerProfileId, # required

        refId => $refId, # Optional

        customerType => $customerType, # Optional
        billTo => { # Optional, all sub items are Optional
            firstName => $firstName,
            lastName  => $lastName,
            company   => $company,
            address   => $address,
            city      => $city,
            state     => $state,
            zip       => $zip,
            country   => $country,
            phoneNumber => $phoneNumber,
            faxNumber => $faxNumber
        },

        creditCard => { # required when the payment profile is credit card
            cardNumber => $cardNumber,
            expirationDate => $expirationDate, # YYYY-MM
            cardCode => $cardCode,  # Optional
        },
        bankAccount => { # required when the payment profile is bank account
            accountType => $accountType, # Optional, one of checking, savings, businessChecking
            routingNumber => $routingNumber,
            accountNumber => $accountNumber,
            nameOnAccount => $nameOnAccount,
            echeckType => $echeckType, # Optionaal, one of CCD, PPD, TEL, WEB
            bankName   => $bankName, # Optional
        },
    );

=cut

sub createCustomerPaymentProfileRequest {
    my $self = shift;
    my $args = scalar @_ % 2 ? shift : { @_ };

    my $xml;
    my $writer = XML::Writer->new(OUTPUT => \$xml);
    $writer->startTag('createCustomerPaymentProfileRequest', 'xmlns' => 'AnetApi/xml/v1/schema/AnetApiSchema.xsd');
    $writer->startTag('merchantAuthentication');
    $writer->dataElement('name', $self->{login});
    $writer->dataElement('transactionKey', $self->{transactionKey});
    $writer->endTag('merchantAuthentication');
    $writer->dataElement('refId', $args->{refId}) if exists $args->{refId};
    $writer->dataElement('customerProfileId', $args->{customerProfileId});
    $writer->startTag('paymentProfile');
    $writer->dataElement('customerType', $args->{'customerType'}) if exists $args->{'customerType'};

    my @flds = ('firstName', 'lastName', 'company', 'address', 'city', 'state', 'zip', 'country', 'phoneNumber', 'faxNumber');
    my $addr = exists $args->{billTo} ? $args->{billTo} : $args;
    if (grep { exists $addr->{$_} } @flds) {
        $writer->startTag('billTo');
        foreach my $k (@flds) {
            $writer->dataElement($k, $addr->{$k})
                if exists $addr->{$k};
        }
        $writer->endTag('billTo');
    }

    $writer->startTag('payment');

    if (exists $args->{creditCard}) {
        $writer->startTag('creditCard');
        foreach my $k ('cardNumber', 'expirationDate', 'cardCode') {
            $writer->dataElement($k, $args->{creditCard}->{$k})
                if exists $args->{creditCard}->{$k};
        }
        $writer->endTag('creditCard');
    }
    if (exists $args->{bankAccount}) {
        $writer->startTag('bankAccount');
        foreach my $k ('accountType', 'routingNumber', 'accountNumber', 'nameOnAccount', 'echeckType', 'bankName') {
            $writer->dataElement($k, $args->{bankAccount}->{$k});
        }
        $writer->endTag('bankAccount');
    }

    $writer->endTag('payment');
    $writer->endTag('paymentProfile');

    if ($self->{test_mode}) {
        $writer->dataElement('validationMode', 'testMode');
    }
    $writer->endTag('createCustomerPaymentProfileRequest');

    $xml = '<?xml version="1.0" encoding="utf-8"?>' . "\n" . $xml;
    print "<!-- $xml -->\n\n" if $self->{debug};
    my $resp = $self->{ua}->post($self->{url}, Content => $xml, 'Content-Type' => 'text/xml');
    print "<!-- " . $resp->content . " -->\n\n" if $self->{debug};

    my $d = XMLin($resp->content, SuppressEmpty => '');
    return $d;
}

=pod

=head3 createCustomerShippingAddressRequest

Create a new customer shipping address for an existing customer profile. You can create up to 100 customer shipping addresses for each customer profile.

    $cim->createCustomerShippingAddressRequest(
        customerProfileId => $customerProfileId, # required

        refId => $refId, # Optional

        firstName => $firstName,
        lastName  => $lastName,
        company   => $company,
        address   => $address,
        city      => $city,
        state     => $state,
        zip       => $zip,
        country   => $country,
        phoneNumber => $phoneNumber,
        faxNumber => $faxNumber
    );

=cut

sub createCustomerShippingAddressRequest {
    my $self = shift;
    my $args = scalar @_ % 2 ? shift : { @_ };

    my $xml;
    my $writer = XML::Writer->new(OUTPUT => \$xml);
    $writer->startTag('createCustomerShippingAddressRequest', 'xmlns' => 'AnetApi/xml/v1/schema/AnetApiSchema.xsd');
    $writer->startTag('merchantAuthentication');
    $writer->dataElement('name', $self->{login});
    $writer->dataElement('transactionKey', $self->{transactionKey});
    $writer->endTag('merchantAuthentication');
    $writer->dataElement('refId', $args->{refId}) if exists $args->{refId};
    $writer->dataElement('customerProfileId', $args->{customerProfileId});
    $writer->startTag('address');

    my @flds = ('firstName', 'lastName', 'company', 'address', 'city', 'state', 'zip', 'country', 'phoneNumber', 'faxNumber');
    my $addr = exists $args->{shipToList} ? $args->{shipToList} : $args;
    foreach my $k (@flds) {
        $writer->dataElement($k, $addr->{$k})
            if exists $addr->{$k};
    }

    $writer->endTag('address');

    if ($self->{test_mode}) {
        $writer->dataElement('validationMode', 'testMode');
    }
    $writer->endTag('createCustomerShippingAddressRequest');

    $xml = '<?xml version="1.0" encoding="utf-8"?>' . "\n" . $xml;
    print "<!-- $xml -->\n\n" if $self->{debug};
    my $resp = $self->{ua}->post($self->{url}, Content => $xml, 'Content-Type' => 'text/xml');
    print "<!-- " . $resp->content . " -->\n\n" if $self->{debug};

    my $d = XMLin($resp->content, SuppressEmpty => '');
    return $d;
}

=pod

=head3 createCustomerProfileTransaction

Create a new payment transaction from an existing customer profile.

    $cim->createCustomerProfileTransaction(
        'profileTransAuthCapture', # or others like profileTransAuthOnly

        refId => $refId, # Optional, reference id

        amount => $amount,
        tax => { # Optional
            amount => $tax_amount,
            name   => $tax_name,
            description => $tax_description
        },
        shipping => { # Optional
            amount => $tax_amount,
            name   => $tax_name,
            description => $tax_description
        },
        duty => { # Optional
            amount => $tax_amount,
            name   => $tax_name,
            description => $tax_description
        },

        lineItems => [ { # Optional
            itemId => $itemId,
            name => $name,
            description => $description,
            quantity => $quantity,
            unitPrice => $unitPrice,
            taxable => $taxable,
        } ],

        customerProfileId => $customerProfileId,
        customerPaymentProfileId => $customerPaymentProfileId,
        customerShippingAddressId => $customerShippingAddressId,

        extraOptions => $extraOptions, # Optional

        ### Only required for profileTransPriorAuthCapture: For Prior Authorization and CaptureTransactions
        ### and profileTransRefund: For Refund Transactions
        ### and profileTransVoid: For Void Transactions
        transId => $transId,

        ### Only partly required for profileTransRefund: For Refund Transactions
        creditCardNumberMasked => $creditCardNumberMasked,
        bankRoutingNumberMasked => $bankRoutingNumberMasked,
        bankAccountNumberMasked => $bankAccountNumberMasked,

        ### rest are not for profileTransPriorAuthCapture
        order => { # Optional
            invoiceNumber => $invoiceNumber,
            description => $description,
            purchaseOrderNumber => $purchaseOrderNumber,
        },
        taxExempt => 'true', # optional
        recurringBilling => 'false', # optional
        cardCode => $cardCode, # Required only when the merchant would like to use the Card Code Verification (CCV) filter
        splitTenderId => $splitTenderId, # Required for second and subsequent transactions related to a partial authorizaqtion transaction.

        #### ONLY required for profileTransCaptureOnly: the Capture Only transaction type.
        approvalCode => $approvalCode,
    );

The first argument can be one of

=over 4

=item * profileTransAuthOnly

For Authorization Only Transactions

=item * profileTransAuthCapture

For Authorization and Capture Transactions

=item * profileTransCaptureOnly

For Capture Only Transactions

=item * profileTransPriorAuthCapture

For Prior Authorization and CaptureTransactions

=item * profileTransRefund

For Refund Transactions

=item * profileTransVoid

For Void Transactions

    $cim->createCustomerProfileTransaction(
        'profileTransVoid', # or others like profileTransAuthOnly

        refId => $refId, # Optional, reference id

        customerProfileId => $customerProfileId,
        customerPaymentProfileId => $customerPaymentProfileId,
        customerShippingAddressId => $customerShippingAddressId,

        extraOptions => $extraOptions, # Optional

        transId => $transId,
    );

=back

=cut

sub createCustomerProfileTransaction {
    my $self = shift;
    my $trans_type = shift;
    my $args = scalar @_ % 2 ? shift : { @_ };

    my $xml;
    my $writer = XML::Writer->new(OUTPUT => \$xml);
    $writer->startTag('createCustomerProfileTransactionRequest', 'xmlns' => 'AnetApi/xml/v1/schema/AnetApiSchema.xsd');
    $writer->startTag('merchantAuthentication');
    $writer->dataElement('name', $self->{login});
    $writer->dataElement('transactionKey', $self->{transactionKey});
    $writer->endTag('merchantAuthentication');
    $writer->dataElement('refId', $args->{refId}) if exists $args->{refId};
    $writer->startTag('transaction');
    $writer->startTag($trans_type); # profileTransAuthOnly, profileTransPriorAuthCapture etc
    $writer->dataElement('amount', $args->{amount});

    foreach my $type ('tax', 'shipping', 'duty') {
        next unless exists $args->{$type};
        $writer->startTag($type);
        foreach my $k ('amount', 'name', 'description') {
            $writer->dataElement($k, $args->{$type}->{$k})
                if exists $args->{$type}->{$k};
        }
        $writer->endTag($type);
    }

    # lineItems
    if (exists $args->{lineItems}) {
        my @lineItems = (ref($args->{lineItems}) eq 'ARRAY') ? @{$args->{lineItems}} : ($args->{lineItems});
        foreach my $lineItem (@lineItems) {
            $writer->startTag('lineItems');
            foreach my $k ('itemId', 'name', 'description', 'quantity', 'unitPrice', 'taxable') {
                $writer->dataElement($k, $lineItem->{$k})
                    if exists $lineItem->{$k};
            }
            $writer->endTag('lineItems');
        }
    }

    $writer->dataElement('customerProfileId', $args->{customerProfileId});
    $writer->dataElement('customerPaymentProfileId', $args->{customerPaymentProfileId});
    $writer->dataElement('customerShippingAddressId', $args->{customerShippingAddressId})
        if $args->{customerShippingAddressId};

    if ($trans_type eq 'profileTransRefund') {
        foreach my $k ('creditCardNumberMasked', 'bankRoutingNumberMasked', 'bankAccountNumberMasked') {
            $writer->dataElement($k, $args->{$k})
                if exists $args->{$k};
        }
    }

    # order
    if (exists $args->{order}) {
        $writer->startTag('order');
        foreach my $k ('invoiceNumber', 'description', 'purchaseOrderNumber') {
            $writer->dataElement($k, $args->{order}->{$k})
                if exists $args->{order}->{$k};
        }
        $writer->endTag('order');
    }

    $writer->dataElement('transId', $args->{transId})
        if ( exists $args->{transId} and ($trans_type eq 'profileTransPriorAuthCapture' or $trans_type eq 'profileTransRefund' or $trans_type eq 'profileTransVoid') );

    $writer->dataElement('taxExempt', $args->{taxExempt})
        if exists $args->{taxExempt};
    $writer->dataElement('recurringBilling', $args->{recurringBilling})
        if exists $args->{recurringBilling};
    $writer->dataElement('cardCode', $args->{cardCode}) if exists $args->{cardCode};
    $writer->dataElement('splitTenderId', $args->{splitTenderId})
        if exists $args->{splitTenderId};
    $writer->dataElement('approvalCode', $args->{approvalCode})
        if exists $args->{approvalCode} and $trans_type eq 'profileTransCaptureOnly';

    $writer->endTag($trans_type);
    $writer->endTag('transaction');

    $writer->dataElement('extraOptions', $args->{extraOptions})
        if exists $args->{extraOptions};

    $writer->endTag('createCustomerProfileTransactionRequest');

    $xml = '<?xml version="1.0" encoding="utf-8"?>' . "\n" . $xml;
    print "<!-- $xml -->\n\n" if $self->{debug};
    my $resp = $self->{ua}->post($self->{url}, Content => $xml, 'Content-Type' => 'text/xml');
    print "<!-- " . $resp->content . " -->\n\n" if $self->{debug};

    my $d = XMLin($resp->content, SuppressEmpty => '');

    print "<!-- $xml -->\n\n" if $self->{debug};
    return $d;
}

=pod

=head3 deleteCustomerProfile

Delete an existing customer profile along with all associated customer payment profiles and customer shipping addresses.

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
    $writer->endTag('deleteCustomerProfileRequest');

    $xml = '<?xml version="1.0" encoding="utf-8"?>' . "\n" . $xml;
    print "<!-- $xml -->\n\n" if $self->{debug};
    my $resp = $self->{ua}->post($self->{url}, Content => $xml, 'Content-Type' => 'text/xml');
    print "<!-- " . $resp->content . " -->\n\n" if $self->{debug};

    my $d = XMLin($resp->content, SuppressEmpty => '');
    return $d;
}

=pod

=head3 deleteCustomerPaymentProfileRequest

Delete a customer payment profile from an existing customer profile.

    $cim->deleteCustomerPaymentProfileRequest($customerProfileId, $customerPaymentProfileId);

=cut

sub deleteCustomerPaymentProfileRequest {
    my ($self, $customerProfileId, $customerPaymentProfileId) = @_;

    my $xml;
    my $writer = XML::Writer->new(OUTPUT => \$xml);
    $writer->startTag('deleteCustomerPaymentProfileRequest', 'xmlns' => 'AnetApi/xml/v1/schema/AnetApiSchema.xsd');
    $writer->startTag('merchantAuthentication');
    $writer->dataElement('name', $self->{login});
    $writer->dataElement('transactionKey', $self->{transactionKey});
    $writer->endTag('merchantAuthentication');
    $writer->dataElement('customerProfileId', $customerProfileId);
    $writer->dataElement('customerPaymentProfileId', $customerPaymentProfileId);
    if ($self->{test_mode}) {
        $writer->dataElement('validationMode', 'testMode');
    }
    $writer->endTag('deleteCustomerPaymentProfileRequest');

    $xml = '<?xml version="1.0" encoding="utf-8"?>' . "\n" . $xml;
    print "<!-- $xml -->\n\n" if $self->{debug};
    my $resp = $self->{ua}->post($self->{url}, Content => $xml, 'Content-Type' => 'text/xml');
    print "<!-- " . $resp->content . " -->\n\n" if $self->{debug};

    my $d = XMLin($resp->content, SuppressEmpty => '');
    return $d;
}

=pod

=head3 deleteCustomerShippingAddressRequest

Delete a customer shipping address from an existing customer profile.

    $cim->deleteCustomerShippingAddressRequest($customerProfileId, $customerAddressId);

=cut

sub deleteCustomerShippingAddressRequest {
    my ($self, $customerProfileId, $customerAddressId) = @_;

    my $xml;
    my $writer = XML::Writer->new(OUTPUT => \$xml);
    $writer->startTag('deleteCustomerShippingAddressRequest', 'xmlns' => 'AnetApi/xml/v1/schema/AnetApiSchema.xsd');
    $writer->startTag('merchantAuthentication');
    $writer->dataElement('name', $self->{login});
    $writer->dataElement('transactionKey', $self->{transactionKey});
    $writer->endTag('merchantAuthentication');
    $writer->dataElement('customerProfileId', $customerProfileId);
    $writer->dataElement('customerAddressId', $customerAddressId);
    if ($self->{test_mode}) {
        $writer->dataElement('validationMode', 'testMode');
    }
    $writer->endTag('deleteCustomerShippingAddressRequest');

    $xml = '<?xml version="1.0" encoding="utf-8"?>' . "\n" . $xml;
    print "<!-- $xml -->\n\n" if $self->{debug};
    my $resp = $self->{ua}->post($self->{url}, Content => $xml, 'Content-Type' => 'text/xml');
    print "<!-- " . $resp->content . " -->\n\n" if $self->{debug};

    my $d = XMLin($resp->content, SuppressEmpty => '');
    return $d;
}

=pod

=head3 getCustomerProfileIds

Retrieve all customer profile IDs you have previously created.

    my @ProfileIds = $cim->getCustomerProfileIds;

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
    $writer->endTag('getCustomerProfileIdsRequest');

    $xml = '<?xml version="1.0" encoding="utf-8"?>' . "\n" . $xml;
    print "<!-- $xml -->\n\n" if $self->{debug};
    my $resp = $self->{ua}->post($self->{url}, Content => $xml, 'Content-Type' => 'text/xml');
    print "<!-- " . $resp->content . " -->\n\n" if $self->{debug};

    my $d = XMLin($resp->content, SuppressEmpty => '');

    return () unless $d->{ids};

    my $id_num = $d->{ids}->{numericString};
    my @ids = ref($id_num) eq 'ARRAY' ? @$id_num
            : defined $id_num         ? ($id_num)
            :                           ();

    return @ids;
}

=pod

=head3 getCustomerProfile

Retrieve an existing customer profile along with all the associated customer payment profiles and customer shipping addresses.

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
    $writer->endTag('getCustomerProfileRequest');

    $xml = '<?xml version="1.0" encoding="utf-8"?>' . "\n" . $xml;
    print "<!-- $xml -->\n\n" if $self->{debug};
    my $resp = $self->{ua}->post($self->{url}, Content => $xml, 'Content-Type' => 'text/xml');
    print "<!-- " . $resp->content . " -->\n\n" if $self->{debug};

    my $d = XMLin($resp->content, SuppressEmpty => '');
    return $d;
}

=pod

=head3 getCustomerPaymentProfileRequest

Retrieve a customer payment profile for an existing customer profile.

    $cim->getCustomerPaymentProfileRequest($customerProfileId, $customerPaymentProfileId);

=cut

sub getCustomerPaymentProfileRequest {
    my ($self, $customerProfileId, $customerPaymentProfileId) = @_;

    my $xml;
    my $writer = XML::Writer->new(OUTPUT => \$xml);
    $writer->startTag('getCustomerPaymentProfileRequest', 'xmlns' => 'AnetApi/xml/v1/schema/AnetApiSchema.xsd');
    $writer->startTag('merchantAuthentication');
    $writer->dataElement('name', $self->{login});
    $writer->dataElement('transactionKey', $self->{transactionKey});
    $writer->endTag('merchantAuthentication');
    $writer->dataElement('customerProfileId', $customerProfileId);
    $writer->dataElement('customerPaymentProfileId', $customerPaymentProfileId);
    if ($self->{test_mode}) {
        $writer->dataElement('validationMode', 'testMode');
    }
    $writer->endTag('getCustomerPaymentProfileRequest');

    $xml = '<?xml version="1.0" encoding="utf-8"?>' . "\n" . $xml;
    print "<!-- $xml -->\n\n" if $self->{debug};
    my $resp = $self->{ua}->post($self->{url}, Content => $xml, 'Content-Type' => 'text/xml');
    print "<!-- " . $resp->content . " -->\n\n" if $self->{debug};

    my $d = XMLin($resp->content, SuppressEmpty => '');
    return $d;
}

=pod

=head3 getCustomerShippingAddressRequest

Retrieve a customer shipping address for an existing customer profile.

    $cim->getCustomerShippingAddressRequest($customerProfileId, $customerAddressId);

=cut

sub getCustomerShippingAddressRequest {
    my ($self, $customerProfileId, $customerAddressId) = @_;

    my $xml;
    my $writer = XML::Writer->new(OUTPUT => \$xml);
    $writer->startTag('getCustomerShippingAddressRequest', 'xmlns' => 'AnetApi/xml/v1/schema/AnetApiSchema.xsd');
    $writer->startTag('merchantAuthentication');
    $writer->dataElement('name', $self->{login});
    $writer->dataElement('transactionKey', $self->{transactionKey});
    $writer->endTag('merchantAuthentication');
    $writer->dataElement('customerProfileId', $customerProfileId);
    $writer->dataElement('customerAddressId', $customerAddressId);
    if ($self->{test_mode}) {
        $writer->dataElement('validationMode', 'testMode');
    }
    $writer->endTag('getCustomerShippingAddressRequest');

    $xml = '<?xml version="1.0" encoding="utf-8"?>' . "\n" . $xml;
    print "<!-- $xml -->\n\n" if $self->{debug};
    my $resp = $self->{ua}->post($self->{url}, Content => $xml, 'Content-Type' => 'text/xml');
    print "<!-- " . $resp->content . " -->\n\n" if $self->{debug};

    my $d = XMLin($resp->content, SuppressEmpty => '');
    return $d;
}

=pod

=head3 updateCustomerProfile

Update an existing customer profile

    $cim->updateCustomerProfile(
        customerProfileId => $customerProfileId,

        refId => $refId, # Optional

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
    $writer->dataElement('refId', $args->{refId}) if exists $args->{refId};
    $writer->startTag('profile');
    foreach my $k ('merchantCustomerId', 'description', 'email') {
        $writer->dataElement($k, $args->{$k})
            if exists $args->{$k};
    }
    $writer->dataElement('customerProfileId', $args->{customerProfileId});
    $writer->endTag('profile');
    $writer->endTag('updateCustomerProfileRequest');

    $xml = '<?xml version="1.0" encoding="utf-8"?>' . "\n" . $xml;
    print "<!-- $xml -->\n\n" if $self->{debug};
    my $resp = $self->{ua}->post($self->{url}, Content => $xml, 'Content-Type' => 'text/xml');
    print "<!-- " . $resp->content . " -->\n\n" if $self->{debug};

    my $d = XMLin($resp->content, SuppressEmpty => '');
    return $d;
}

=pod

=head3 updateCustomerPaymentProfile

Update a customer payment profile for an existing customer profile.

    $cim->updateCustomerPaymentProfile(
        customerProfileId => $customerProfileId,
        customerPaymentProfileId => $customerPaymentProfileId,

        refId => $refId, # Optional

        customerType => $customerType, # Optional
        billTo => { # Optional, all sub items are Optional
            firstName => $firstName,
            lastName  => $lastName,
            company   => $company,
            address   => $address,
            city      => $city,
            state     => $state,
            zip       => $zip,
            country   => $country,
            phoneNumber => $phoneNumber,
            faxNumber => $faxNumber
        },

        creditCard => { # required when the payment profile is credit card
            cardNumber => $cardNumber,
            expirationDate => $expirationDate, # YYYY-MM
            cardCode => $cardCode,  # Optional
        },
        bankAccount => { # required when the payment profile is bank account
            accountType => $accountType, # Optional, one of checking, savings, businessChecking
            routingNumber => $routingNumber,
            accountNumber => $accountNumber,
            nameOnAccount => $nameOnAccount,
            echeckType => $echeckType, # Optionaal, one of CCD, PPD, TEL, WEB
            bankName   => $bankName, # Optional
        },
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
    $writer->dataElement('refId', $args->{refId}) if exists $args->{refId};
    $writer->dataElement('customerProfileId', $args->{customerProfileId});

    $writer->startTag('paymentProfile');
    $writer->dataElement('customerType', $args->{'customerType'}) if exists $args->{'customerType'};

    my @flds = ('firstName', 'lastName', 'company', 'address', 'city', 'state', 'zip', 'country', 'phoneNumber', 'faxNumber');
    my $addr = exists $args->{billTo} ? $args->{billTo} : $args;
    if (grep { exists $addr->{$_} } @flds) {
        $writer->startTag('billTo');
        foreach my $k (@flds) {
            $writer->dataElement($k, $addr->{$k})
                if exists $addr->{$k};
        }
        $writer->endTag('billTo');
    }

    $writer->startTag('payment');

    if (exists $args->{creditCard}) {
        $writer->startTag('creditCard');
        foreach my $k ('cardNumber', 'expirationDate', 'cardCode') {
            $writer->dataElement($k, $args->{creditCard}->{$k})
                if exists $args->{creditCard}->{$k};
        }
        $writer->endTag('creditCard');
    }
    if (exists $args->{bankAccount}) {
        $writer->startTag('bankAccount');
        foreach my $k ('accountType', 'routingNumber', 'accountNumber', 'nameOnAccount', 'echeckType', 'bankName') {
            $writer->dataElement($k, $args->{bankAccount}->{$k});
        }
        $writer->endTag('bankAccount');
    }

    $writer->endTag('payment');
    $writer->dataElement('customerPaymentProfileId', $args->{customerPaymentProfileId});
    $writer->endTag('paymentProfile');

    if ($self->{test_mode}) {
        $writer->dataElement('validationMode', 'testMode');
    }
    $writer->endTag('updateCustomerPaymentProfileRequest');

    $xml = '<?xml version="1.0" encoding="utf-8"?>' . "\n" . $xml;
    print "<!-- $xml -->\n\n" if $self->{debug};
    my $resp = $self->{ua}->post($self->{url}, Content => $xml, 'Content-Type' => 'text/xml');
    print "<!-- " . $resp->content . " -->\n\n" if $self->{debug};

    my $d = XMLin($resp->content, SuppressEmpty => '');
    return $d;
}

=pod

=head3 updateCustomerShippingAddress

Update a shipping address for an existing customer profile.

    $cim->updateCustomerShippingAddress(
        customerProfileId => $customerProfileId,
        customerAddressId => $customerAddressId,

        refId => $refId, # Optional

        firstName => $firstName,
        lastName  => $lastName,
        company   => $company,
        address   => $address,
        city      => $city,
        state     => $state,
        zip       => $zip,
        country   => $country,
        phoneNumber => $phoneNumber,
        faxNumber => $faxNumber
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
    $writer->dataElement('refId', $args->{refId}) if exists $args->{refId};
    $writer->dataElement('customerProfileId', $args->{customerProfileId})
        if exists $args->{customerProfileId};
    $writer->startTag('address');

    my @flds = ('firstName', 'lastName', 'company', 'address', 'city', 'state', 'zip', 'country', 'phoneNumber', 'faxNumber');
    my $addr = exists $args->{shipToList} ? $args->{shipToList} : $args;
    foreach my $k (@flds) {
        $writer->dataElement($k, $addr->{$k})
            if exists $addr->{$k};
    }

    $writer->dataElement('customerAddressId', $args->{customerAddressId});
    $writer->endTag('address');

    $writer->endTag('updateCustomerShippingAddressRequest');

    $xml = '<?xml version="1.0" encoding="utf-8"?>' . "\n" . $xml;
    print "<!-- $xml -->\n\n" if $self->{debug};
    my $resp = $self->{ua}->post($self->{url}, Content => $xml, 'Content-Type' => 'text/xml');
    print "<!-- " . $resp->content . " -->\n\n" if $self->{debug};

    my $d = XMLin($resp->content, SuppressEmpty => '');
    return $d;
}

=pod

=head3 updateSplitTenderGroupRequest

Update the status of a split tender group (a group of transactions, each of which pays for part of one order).

    $cim->updateSplitTenderGroupRequest($splitTenderId, $splitTenderStatus);
    # splitTenderStatus can be voided or completed.

=cut

sub updateSplitTenderGroupRequest {
    my ($self, $splitTenderId, $splitTenderStatus) = @_;

    my $xml;
    my $writer = XML::Writer->new(OUTPUT => \$xml);
    $writer->startTag('updateSplitTenderGroupRequest', 'xmlns' => 'AnetApi/xml/v1/schema/AnetApiSchema.xsd');
    $writer->startTag('merchantAuthentication');
    $writer->dataElement('name', $self->{login});
    $writer->dataElement('transactionKey', $self->{transactionKey});
    $writer->endTag('merchantAuthentication');
    $writer->dataElement('splitTenderId', $splitTenderId);
    $writer->dataElement('splitTenderStatus', $splitTenderStatus);
    $writer->endTag('updateSplitTenderGroupRequest');

    $xml = '<?xml version="1.0" encoding="utf-8"?>' . "\n" . $xml;
    print "<!-- $xml -->\n\n" if $self->{debug};
    my $resp = $self->{ua}->post($self->{url}, Content => $xml, 'Content-Type' => 'text/xml');
    print "<!-- " . $resp->content . " -->\n\n" if $self->{debug};

    my $d = XMLin($resp->content, SuppressEmpty => '');
    return $d;
}

=pod

=head3 validateCustomerPaymentProfile

Verify an existing customer payment profile by generating a test transaction.

    $cim->validateCustomerPaymentProfile(
        customerProfileId => $customerProfileId,
        customerPaymentProfileId => $customerPaymentProfileId,
        customerShippingAddressId => $customerShippingAddressId,

        cardCode => $cardCode, # Optional
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
    print "<!-- $xml -->\n\n" if $self->{debug};
    my $resp = $self->{ua}->post($self->{url}, Content => $xml, 'Content-Type' => 'text/xml');
    print "<!-- " . $resp->content . " -->\n\n" if $self->{debug};

    my $d = XMLin($resp->content, SuppressEmpty => '');
    return $d;
}

1;
