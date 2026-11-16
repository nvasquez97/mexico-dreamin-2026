/**
 * Registered-customer flows: sign-up, login helpers, shipment request, my shipments
 * (REQ-005, REQ-006, REQ-007).
 *
 * SHARING JUSTIFICATION: system mode. Shipment__c, Account and Contact are Private and not shared with
 * external users. Registration must create an account, contact and user on behalf of the guest.
 * For every authenticated operation the customer's account is derived on the server from the running
 * user's contact, never from client input (BR-07); the price is always recomputed on the server (BR-08)
 * and the status is always Requested (BR-09).
 */
public without sharing class CustomerService {
    public static final String CUSTOMER_PROFILE = 'RutaCargo Customer';
    public static final String OWNER_ROLE = 'RutaCargo_Customer_Owner';
    public static final String USERNAME_SUFFIX = '.rutacargo';
    private static final Pattern EMAIL_PATTERN = Pattern.compile('^[A-Za-z0-9._%+\'-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}$');

    /**
     * Tests set this because System.setPassword needs the site's sender address to be verified, which is a manual
     * org step. The real call is covered by the manual check in the README.
     */
    @TestVisible
    private static Boolean skipSetPasswordInTest = false;

    public class CustomerException extends Exception {
    }

    // ---- REQ-005 ---------------------------------------------------------------------------

    /**
     * AC-005.1 to AC-005.4.
     * @param customerType Individual or Business
     * @param accountName name or legal name
     * @param firstName contact first name
     * @param lastName contact last name
     * @param email email (becomes the login)
     * @param phone phone
     * @param password password (10+ characters, letters and numbers)
     * @return success, or a message; "alreadyRegistered" is signalled with the message text ALREADY_REGISTERED
     */
    public static RutaCargoDtos.ActionResult register(
        String customerType, String accountName, String firstName, String lastName, String email, String phone, String password
    ) {
        String cleanEmail = email?.trim().toLowerCase();
        String problem = registrationProblem(customerType, accountName, firstName, lastName, cleanEmail, phone, password);
        if (problem != null) {
            return fail(problem);
        }
        if (userExistsFor(cleanEmail)) {
            return fail('ALREADY_REGISTERED');
        }
        Id ownerId = registrationOwnerId();
        Id profileId = customerProfileId();
        if (ownerId == null || profileId == null) {
            return fail('Sign-up is temporarily unavailable. Please try again later.');
        }
        Savepoint savepoint = Database.setSavepoint();
        try {
            Account account = new Account(
                Name = accountName.trim(), Customer_Type__c = customerType, Phone = phone.trim(), OwnerId = ownerId
            );
            Database.insert(account, AccessLevel.SYSTEM_MODE);
            Contact contact = new Contact(
                AccountId = account.Id, FirstName = firstName.trim(), LastName = lastName.trim(), Email = cleanEmail, Phone = phone.trim()
            );
            Database.insert(contact, AccessLevel.SYSTEM_MODE);
            User customer = new User(
                Username = cleanEmail + USERNAME_SUFFIX,
                Email = cleanEmail,
                FirstName = firstName.trim(),
                LastName = lastName.trim(),
                Alias = (firstName.trim().left(1) + lastName.trim()).left(4) + String.valueOf(Math.abs(Crypto.getRandomInteger())).left(3),
                CommunityNickname = 'rc' + String.valueOf(Math.abs(Crypto.getRandomLong())).left(14),
                ProfileId = profileId,
                ContactId = contact.Id,
                TimeZoneSidKey = 'America/Mexico_City',
                LocaleSidKey = 'en_US',
                EmailEncodingKey = 'UTF-8',
                LanguageLocaleKey = 'en_US'
            );
            Database.insert(customer, AccessLevel.SYSTEM_MODE);
            if (!skipSetPasswordInTest) {
                System.setPassword(customer.Id, password);
            }
        } catch (Exception e) {
            Database.rollback(savepoint);
            return fail('We could not create your account. Check your data and try again.');
        }
        RutaCargoDtos.ActionResult ok = new RutaCargoDtos.ActionResult();
        ok.success = true;
        ok.message = 'Your account was created. You can log in now.';
        return ok;
    }

    /**
     * @param email email typed on the login form
     * @return the username of the active customer with that email, or null
     */
    public static String usernameFor(String email) {
        if (String.isBlank(email)) {
            return null;
        }
        String cleanEmail = email.trim().toLowerCase();
        List<User> users = [
            SELECT Username FROM User
            WHERE Email = :cleanEmail AND IsActive = TRUE AND Profile.Name = :CUSTOMER_PROFILE
            WITH SYSTEM_MODE LIMIT 1
        ];
        return users.isEmpty() ? null : users[0].Username;
    }

    // ---- REQ-006 ---------------------------------------------------------------------------

    /**
     * AC-006.2. Price preview according to BR-08.
     * @param serviceType Standard or Express
     * @param weightKg weight in kg
     * @param declaredValue declared value in MXN
     * @return the price or a message
     */
    public static RutaCargoDtos.ActionResult quote(String serviceType, Decimal weightKg, Decimal declaredValue) {
        requireCustomerAccount();
        if (!ShipmentRules.isWithinLimits(weightKg, declaredValue)) {
            return fail('The maximum weight is 30 kg and the maximum declared value is 50,000 MXN.');
        }
        RutaCargoDtos.ActionResult result = new RutaCargoDtos.ActionResult();
        try {
            result.price = ShipmentRules.calculatePrice(serviceType, weightKg, declaredValue);
        } catch (ShipmentRules.RuleException e) {
            return fail(e.getMessage());
        }
        result.success = true;
        return result;
    }

    /**
     * AC-006.1 to AC-006.6.
     * @return success with the tracking number, or the reason
     */
    public static RutaCargoDtos.ActionResult createShipment(
        String pickupAddress, String pickupCity, String pickupPostalCode, Date pickupDate,
        String recipientName, String recipientAddress, String recipientCity, String recipientPostalCode,
        String recipientPhone, String recipientEmail, String serviceType, Decimal weightKg,
        String packageDescription, Decimal declaredValue, String customerReference, String deliveryInstructions
    ) {
        Id accountId = requireCustomerAccount();
        String problem = shipmentProblem(
            pickupAddress, pickupCity, pickupPostalCode, pickupDate, recipientName, recipientAddress, recipientCity,
            recipientPostalCode, recipientPhone, recipientEmail, serviceType, weightKg, packageDescription,
            declaredValue, customerReference, deliveryInstructions
        );
        if (problem != null) {
            return fail(problem);
        }
        Decimal price = ShipmentRules.calculatePrice(serviceType, weightKg, declaredValue);
        Date estimate = ShipmentRules.estimatedDelivery(pickupDate, serviceType);
        Shipment__c shipment = new Shipment__c(
            Account__c = accountId,
            Status__c = 'Requested',
            Service_Type__c = serviceType,
            Pickup_Address__c = pickupAddress.trim(),
            Origin_City__c = pickupCity.trim(),
            Pickup_Postal_Code__c = pickupPostalCode.trim(),
            Pickup_Date__c = pickupDate,
            Recipient_Name__c = recipientName.trim(),
            Recipient_Address__c = recipientAddress.trim(),
            Destination_City__c = recipientCity.trim(),
            Destination_Postal_Code__c = recipientPostalCode.trim(),
            Recipient_Phone__c = recipientPhone.trim(),
            Recipient_Email__c = recipientEmail.trim(),
            Package_Description__c = packageDescription.trim(),
            Weight_Kg__c = weightKg,
            Declared_Value__c = declaredValue,
            Price__c = price,
            Estimated_Delivery__c = estimate,
            Original_Estimated_Delivery__c = estimate,
            Reschedule_Count__c = 0,
            Customer_Reference__c = String.isBlank(customerReference) ? null : customerReference.trim(),
            Delivery_Instructions__c = String.isBlank(deliveryInstructions) ? null : deliveryInstructions.trim()
        );
        Database.insert(shipment, AccessLevel.SYSTEM_MODE);
        Shipment__c saved = [SELECT Name FROM Shipment__c WHERE Id = :shipment.Id WITH SYSTEM_MODE];
        RutaCargoDtos.ActionResult result = new RutaCargoDtos.ActionResult();
        result.success = true;
        result.trackingNumber = saved.Name;
        result.price = price;
        result.estimatedDelivery = estimate;
        return result;
    }

    // ---- REQ-007 ---------------------------------------------------------------------------

    /**
     * AC-007.1, AC-007.2.
     * @param status optional status filter
     * @param term optional search over tracking number, recipient and reference
     * @return the caller's shipments, newest first
     */
    public static List<RutaCargoDtos.MyShipment> listMine(String status, String term) {
        Id accountId = requireCustomerAccount();
        if (!String.isBlank(status) && !ShipmentSelector.STATUSES.contains(status)) {
            throw new CustomerException('Unknown status.');
        }
        String safeTerm = term == null ? null : term.trim().left(80);
        List<RutaCargoDtos.MyShipment> result = new List<RutaCargoDtos.MyShipment>();
        for (Shipment__c row : ShipmentSelector.forAccount(accountId, status, safeTerm)) {
            result.add(summary(row));
        }
        return result;
    }

    /**
     * AC-007.3. Returns null when the shipment does not belong to the caller (BR-07).
     * @param trackingNumber tracking number
     * @return detail or null
     */
    public static RutaCargoDtos.ShipmentDetail getMine(String trackingNumber) {
        Id accountId = requireCustomerAccount();
        if (String.isBlank(trackingNumber)) {
            return null;
        }
        Shipment__c row = ShipmentSelector.oneForAccount(accountId, trackingNumber.trim());
        if (row == null) {
            return null;
        }
        RutaCargoDtos.ShipmentDetail detail = new RutaCargoDtos.ShipmentDetail();
        detail.summary = summary(row);
        detail.pickupAddress = row.Pickup_Address__c;
        detail.pickupPostalCode = row.Pickup_Postal_Code__c;
        detail.pickupDate = row.Pickup_Date__c;
        detail.originCity = row.Origin_City__c;
        detail.recipientAddress = row.Recipient_Address__c;
        detail.destinationPostalCode = row.Destination_Postal_Code__c;
        detail.recipientPhone = row.Recipient_Phone__c;
        detail.recipientEmail = row.Recipient_Email__c;
        detail.deliveryInstructions = row.Delivery_Instructions__c;
        detail.packageDescription = row.Package_Description__c;
        detail.weightKg = row.Weight_Kg__c;
        detail.declaredValue = row.Declared_Value__c;
        detail.estimatedDelivery = row.Estimated_Delivery__c;
        return detail;
    }

    // ---- internals -------------------------------------------------------------------------

    /**
     * Account of the running external user, derived from the user's contact (BR-07).
     * @return the account id
     * @throws CustomerException when the caller is a guest or has no contact
     */
    public static Id requireCustomerAccount() {
        if (UserInfo.getUserType() == 'Guest') {
            throw new CustomerException('Please log in to continue.');
        }
        List<User> users = [SELECT Contact.AccountId FROM User WHERE Id = :UserInfo.getUserId() WITH SYSTEM_MODE LIMIT 1];
        Id accountId = users.isEmpty() ? null : users[0].Contact?.AccountId;
        if (accountId == null) {
            throw new CustomerException('Please log in to continue.');
        }
        return accountId;
    }

    private static RutaCargoDtos.MyShipment summary(Shipment__c row) {
        RutaCargoDtos.MyShipment item = new RutaCargoDtos.MyShipment();
        item.trackingNumber = row.Name;
        item.requestedOn = Date.valueOf(row.CreatedDate.format('yyyy-MM-dd', 'America/Mexico_City'));
        item.recipientName = row.Recipient_Name__c;
        item.destinationCity = row.Destination_City__c;
        item.status = row.Status__c;
        item.serviceType = row.Service_Type__c;
        item.price = row.Price__c;
        item.customerReference = row.Customer_Reference__c;
        return item;
    }

    private static RutaCargoDtos.ActionResult fail(String message) {
        RutaCargoDtos.ActionResult result = new RutaCargoDtos.ActionResult();
        result.success = false;
        result.message = message;
        return result;
    }

    private static String registrationProblem(
        String customerType, String accountName, String firstName, String lastName, String email, String phone, String password
    ) {
        if (customerType != 'Individual' && customerType != 'Business') {
            return 'Choose Individual or Business.';
        }
        if (String.isBlank(accountName) || String.isBlank(firstName) || String.isBlank(lastName) || String.isBlank(phone)) {
            return 'Complete all the fields.';
        }
        if (accountName.length() > 120 || firstName.length() > 40 || lastName.length() > 80 || phone.length() > 40) {
            return 'One of the fields is too long.';
        }
        if (String.isBlank(email) || email.length() > 80 || !EMAIL_PATTERN.matcher(email).matches()) {
            return 'Enter a valid email.';
        }
        if (!ShipmentRules.isValidPassword(password)) {
            return 'The password must have at least 10 characters, with letters and numbers.';
        }
        return null;
    }

    private static String shipmentProblem(
        String pickupAddress, String pickupCity, String pickupPostalCode, Date pickupDate,
        String recipientName, String recipientAddress, String recipientCity, String recipientPostalCode,
        String recipientPhone, String recipientEmail, String serviceType, Decimal weightKg,
        String packageDescription, Decimal declaredValue, String customerReference, String deliveryInstructions
    ) {
        for (String required : new List<String>{
            pickupAddress, pickupCity, recipientName, recipientAddress, recipientCity, recipientPhone, packageDescription
        }) {
            if (String.isBlank(required)) {
                return 'Complete all the required fields.';
            }
        }
        if (pickupAddress.length() > 2000 || recipientAddress.length() > 2000 || pickupCity.length() > 80 || recipientCity.length() > 80 ||
            recipientName.length() > 120 || packageDescription.length() > 255 || recipientPhone.length() > 40 ||
            (customerReference != null && customerReference.length() > 80) ||
            (deliveryInstructions != null && deliveryInstructions.length() > 1000)) {
            return 'One of the fields is too long.';
        }
        if (!ShipmentRules.isValidPostalCode(pickupPostalCode?.trim()) || !ShipmentRules.isValidPostalCode(recipientPostalCode?.trim())) {
            return 'Postal codes must have 5 digits.';
        }
        if (String.isBlank(recipientEmail) || recipientEmail.length() > 80 || !EMAIL_PATTERN.matcher(recipientEmail.trim()).matches()) {
            return 'Enter a valid recipient email.';
        }
        if (serviceType != ShipmentRules.SERVICE_STANDARD && serviceType != ShipmentRules.SERVICE_EXPRESS) {
            return 'Choose Standard or Express.';
        }
        if (!ShipmentRules.isWithinLimits(weightKg, declaredValue)) {
            return 'The maximum weight is 30 kg and the maximum declared value is 50,000 MXN.';
        }
        if (!ShipmentRules.isValidPickupDate(pickupDate)) {
            return 'The pickup date must be a business day between tomorrow and 15 days from today.';
        }
        return null;
    }

    private static Boolean userExistsFor(String email) {
        return ![SELECT Id FROM User WHERE Email = :email WITH SYSTEM_MODE LIMIT 1].isEmpty() ||
            ![SELECT Id FROM Contact WHERE Email = :email AND Account.Customer_Type__c != NULL WITH SYSTEM_MODE LIMIT 1].isEmpty();
    }

    private static Id registrationOwnerId() {
        List<User> owners = [
            SELECT Id FROM User
            WHERE UserRole.DeveloperName = :OWNER_ROLE AND IsActive = TRUE AND UserType = 'Standard'
            WITH SYSTEM_MODE ORDER BY CreatedDate LIMIT 1
        ];
        return owners.isEmpty() ? null : owners[0].Id;
    }

    private static Id customerProfileId() {
        List<Profile> profiles = [SELECT Id FROM Profile WHERE Name = :CUSTOMER_PROFILE WITH SYSTEM_MODE LIMIT 1];
        return profiles.isEmpty() ? null : profiles[0].Id;
    }
}
