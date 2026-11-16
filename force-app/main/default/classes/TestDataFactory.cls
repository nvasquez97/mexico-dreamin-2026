/**
 * Test data for RutaCargo tests. All data is fictional.
 */
@IsTest
public without sharing class TestDataFactory {
    public static final String POSTAL = '64000';

    /**
     * Grants the running user the Support Agent permission set. API 67 runs plain DML/SOQL in user mode,
     * so tests that read or write RutaCargo fields directly need field access, like a real support agent.
     */
    public static void grantSupportAccess() {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            Id permissionSetId = [SELECT Id FROM PermissionSet WHERE Name = 'RutaCargo_Support_Agent' LIMIT 1].Id;
            if ([SELECT COUNT() FROM PermissionSetAssignment WHERE AssigneeId = :UserInfo.getUserId() AND PermissionSetId = :permissionSetId] == 0) {
                insert new PermissionSetAssignment(AssigneeId = UserInfo.getUserId(), PermissionSetId = permissionSetId);
            }
        }
    }

    /**
     * Internal user holding the owner role used for customer accounts created by sign-up.
     * @return the inserted user
     */
    public static User createRegistrationOwner() {
        User owner;
        System.runAs(new User(Id = UserInfo.getUserId())) {
            UserRole role = [SELECT Id FROM UserRole WHERE DeveloperName = :CustomerService.OWNER_ROLE LIMIT 1];
            Profile admin = [SELECT Id FROM Profile WHERE Name = 'System Administrator' LIMIT 1];
            owner = new User(
                Username = 'owner' + System.currentTimeMillis() + '@rutacargo.test', Email = 'owner@rutacargo.test',
                FirstName = 'Site', LastName = 'Owner', Alias = 'sowner', ProfileId = admin.Id, UserRoleId = role.Id,
                TimeZoneSidKey = 'America/Mexico_City', LocaleSidKey = 'en_US', EmailEncodingKey = 'UTF-8', LanguageLocaleKey = 'en_US'
            );
            Database.insert(owner, AccessLevel.SYSTEM_MODE);
        }
        return owner;
    }

    /**
     * Creates a customer (account, contact, external user) directly, without a password, so tests
     * that need a logged-in customer do not depend on the site's email settings. Requires
     * createRegistrationOwner() to have run in @TestSetup.
     * @param email customer email
     * @return the external user with Contact.AccountId populated
     */
    public static User registerCustomer(String email) {
        User owner = [SELECT Id FROM User WHERE UserRole.DeveloperName = :CustomerService.OWNER_ROLE AND IsActive = TRUE LIMIT 1];
        Profile profile = [SELECT Id FROM Profile WHERE Name = :CustomerService.CUSTOMER_PROFILE LIMIT 1];
        Account account;
        Contact contact;
        System.runAs(owner) {
            account = new Account(Name = 'Acme ' + email, Customer_Type__c = 'Business', OwnerId = owner.Id);
            Database.insert(account, AccessLevel.SYSTEM_MODE);
            contact = new Contact(AccountId = account.Id, FirstName = 'Ana', LastName = 'Lopez', Email = email);
            Database.insert(contact, AccessLevel.SYSTEM_MODE);
        }
        User customer = new User(
            Username = email + CustomerService.USERNAME_SUFFIX, Email = email, FirstName = 'Ana', LastName = 'Lopez',
            Alias = 'cust' + String.valueOf(Math.abs(Crypto.getRandomInteger())).left(4),
            CommunityNickname = 'n' + String.valueOf(Math.abs(Crypto.getRandomLong())).left(12),
            ProfileId = profile.Id, ContactId = contact.Id, TimeZoneSidKey = 'America/Mexico_City', LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8', LanguageLocaleKey = 'en_US'
        );
        System.runAs(owner) {
            Database.insert(customer, AccessLevel.SYSTEM_MODE);
        }
        return [SELECT Id, ContactId, Contact.AccountId FROM User WHERE Id = :customer.Id];
    }

    /**
     * @param accountId customer account (may be null)
     * @param status status
     * @param reference order reference
     * @return an inserted shipment with valid data
     */
    public static Shipment__c createShipment(Id accountId, String status, String reference) {
        Shipment__c shipment = new Shipment__c(
            Account__c = accountId, Status__c = status, Service_Type__c = 'Standard', Customer_Reference__c = reference,
            Pickup_Address__c = 'Av. Juarez 100', Pickup_Postal_Code__c = '06000', Pickup_Date__c = ShipmentRules.today(),
            Origin_City__c = 'Ciudad de Mexico', Destination_City__c = 'Monterrey', Recipient_Name__c = 'Luis Perez',
            Recipient_Address__c = 'Calle Hidalgo 45', Destination_Postal_Code__c = POSTAL, Recipient_Phone__c = '8187654321',
            Recipient_Email__c = 'luis@example.com', Delivery_Instructions__c = 'Leave with the doorman',
            Package_Description__c = 'Books', Weight_Kg__c = 2, Declared_Value__c = 1000, Price__c = 171, Carrier_Cost__c = 90,
            Internal_Notes__c = 'internal only', Estimated_Delivery__c = ShipmentRules.today().addDays(3),
            Original_Estimated_Delivery__c = ShipmentRules.today().addDays(3), Reschedule_Count__c = 0,
            Last_Location__c = 'Ciudad de Mexico', Last_Update__c = Datetime.now().addHours(-5)
        );
        Database.insert(shipment, AccessLevel.SYSTEM_MODE);
        return shipment;
    }

    /**
     * @param shipmentId id
     * @return the tracking number (auto-number name)
     */
    public static String trackingOf(Id shipmentId) {
        return [SELECT Name FROM Shipment__c WHERE Id = :shipmentId].Name;
    }
}
