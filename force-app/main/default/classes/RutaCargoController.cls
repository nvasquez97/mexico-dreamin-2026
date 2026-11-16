/**
 * Single entry point for the site's LWCs. Thin and `with sharing`: all elevated-access logic is isolated in
 * the services it calls (each documents why it runs in system mode). Callable by the guest user (public
 * tracking, delivery details, sign-up, login) and by customers (request shipment, my shipments); the
 * customer-only methods verify on the server who is calling (CustomerService.requireCustomerAccount).
 * Methods take individual fields, never whole records, and return DTOs with only the permitted fields.
 */
public with sharing class RutaCargoController {
    // ---- public (guest) --------------------------------------------------------------------

    /** @param searchBy trackingNumber or reference @param rawValues up to 10 values @param sortBy status or estimatedDelivery */
    @AuraEnabled
    public static RutaCargoDtos.TrackingResponse trackShipments(String searchBy, String rawValues, String sortBy) {
        try {
            return TrackingService.search(searchBy, rawValues, sortBy);
        } catch (TrackingService.TrackingException e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    /** @param trackingNumber tracking number @param postalCode destination postal code */
    @AuraEnabled
    public static RutaCargoDtos.DeliveryDetails getDeliveryDetails(String trackingNumber, String postalCode) {
        return RecipientService.getDetails(trackingNumber, postalCode);
    }

    /** @param trackingNumber tracking number @param postalCode destination postal code */
    @AuraEnabled
    public static RutaCargoDtos.ProofResult getProofOfDelivery(String trackingNumber, String postalCode) {
        return RecipientService.getProof(trackingNumber, postalCode);
    }

    /** @param trackingNumber tracking number @param postalCode destination postal code @param newDate new date @param instructions new instructions */
    @AuraEnabled
    public static RutaCargoDtos.DeliveryDetails rescheduleDelivery(String trackingNumber, String postalCode, Date newDate, String instructions) {
        return RecipientService.reschedule(trackingNumber, postalCode, newDate, instructions);
    }

    /** Sign-up (AC-005.1 to AC-005.4). */
    @AuraEnabled
    public static RutaCargoDtos.ActionResult registerCustomer(
        String customerType, String accountName, String firstName, String lastName, String email, String phone, String password
    ) {
        return CustomerService.register(customerType, accountName, firstName, lastName, email, phone, password);
    }

    /**
     * Login (AC-005.5). Returns the URL to navigate to, or throws a generic error that does not reveal
     * whether the email exists.
     * @param email email
     * @param password password
     * @param startUrl ignored: the landing page is always built on the server, so the endpoint cannot be used as an open redirect
     * @return redirect URL
     */
    @AuraEnabled
    public static String login(String email, String password, String startUrl) {
        String username = CustomerService.usernameFor(email);
        PageReference target = username == null || String.isBlank(password)
            ? null
            : Site.login(username, password, Site.getPathPrefix() + '/my-shipments');
        if (target == null) {
            throw new AuraHandledException('Invalid email or password.');
        }
        return target.getUrl();
    }

    /**
     * Password reset link by email (AC-005.6). Always answers the same, so it cannot be used to discover emails.
     * @param email email
     * @return confirmation message
     */
    @AuraEnabled
    public static String forgotPassword(String email) {
        String username = CustomerService.usernameFor(email);
        if (username != null) {
            Site.forgotPassword(username);
        }
        return 'If that email has an account, we sent a link to reset the password.';
    }

    // ---- customers -------------------------------------------------------------------------

    /** Price preview (AC-006.2). */
    @AuraEnabled
    public static RutaCargoDtos.ActionResult quoteShipment(String serviceType, Decimal weightKg, Decimal declaredValue) {
        try {
            return CustomerService.quote(serviceType, weightKg, declaredValue);
        } catch (CustomerService.CustomerException e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    /** Shipment request (AC-006.1 to AC-006.6). */
    @AuraEnabled
    public static RutaCargoDtos.ActionResult requestShipment(
        String pickupAddress, String pickupCity, String pickupPostalCode, Date pickupDate,
        String recipientName, String recipientAddress, String recipientCity, String recipientPostalCode,
        String recipientPhone, String recipientEmail, String serviceType, Decimal weightKg,
        String packageDescription, Decimal declaredValue, String customerReference, String deliveryInstructions
    ) {
        try {
            return CustomerService.createShipment(
                pickupAddress, pickupCity, pickupPostalCode, pickupDate, recipientName, recipientAddress, recipientCity,
                recipientPostalCode, recipientPhone, recipientEmail, serviceType, weightKg, packageDescription,
                declaredValue, customerReference, deliveryInstructions
            );
        } catch (CustomerService.CustomerException e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    /** My shipments (AC-007.1, AC-007.2). */
    @AuraEnabled
    public static List<RutaCargoDtos.MyShipment> getMyShipments(String status, String term) {
        try {
            return CustomerService.listMine(status, term);
        } catch (CustomerService.CustomerException e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    /** One of my shipments (AC-007.3). */
    @AuraEnabled
    public static RutaCargoDtos.ShipmentDetail getMyShipment(String trackingNumber) {
        try {
            return CustomerService.getMine(trackingNumber);
        } catch (CustomerService.CustomerException e) {
            throw new AuraHandledException(e.getMessage());
        }
    }
}
