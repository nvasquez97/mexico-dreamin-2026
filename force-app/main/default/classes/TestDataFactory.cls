/**
 * Builds test data for RutaCargo tests: customer accounts, shipments and the
 * real user types that use the site (site guest, customer site user).
 */
@IsTest
public class TestDataFactory {
    public static final String SITE_GUEST_PROFILE = 'RutaCargo Profile';
    public static final String CUSTOMER_PROFILE = 'RutaCargo Customer';

    /**
     * @return a business customer account (not inserted).
     */
    public static Account buildCustomerAccount(String name) {
        return new Account(
            Name = name,
            Customer_Type__c = 'Business',
            Credit_Limit__c = 100000,
            Credit_Risk__c = 'High'
        );
    }

    /**
     * @return a shipment with every field populated, including internal ones (not inserted).
     */
    public static Shipment__c buildShipment(Id accountId, String status) {
        return new Shipment__c(
            Account__c = accountId,
            Status__c = status,
            Service_Type__c = 'Standard',
            Customer_Reference__c = null,
            Pickup_Address__c = 'Av. Juarez 100, Centro',
            Pickup_Postal_Code__c = '06000',
            Pickup_Date__c = Date.newInstance(2026, 11, 16),
            Origin_City__c = 'Ciudad de Mexico',
            Destination_City__c = 'Monterrey',
            Recipient_Name__c = 'Laura Garza',
            Recipient_Address__c = 'Calle Hidalgo 200, Centro',
            Destination_Postal_Code__c = '64000',
            Recipient_Phone__c = '+52 81 5555 0101',
            Recipient_Email__c = 'laura.garza@example.com',
            Delivery_Instructions__c = 'Ring twice',
            Package_Description__c = 'Books',
            Weight_Kg__c = 2,
            Declared_Value__c = 1000,
            Price__c = 171,
            Carrier_Cost__c = 90,
            Internal_Notes__c = 'Internal note: VIP',
            Estimated_Delivery__c = Date.newInstance(2026, 11, 23),
            Original_Estimated_Delivery__c = Date.newInstance(2026, 11, 23),
            Reschedule_Count__c = 0,
            Last_Location__c = 'Ciudad de Mexico, CDMX',
            Last_Update__c = Datetime.newInstanceGmt(2026, 11, 16, 18, 0, 0)
        );
    }

    /**
     * @return the tracking numbers of the given shipments, read back after insert.
     */
    public static Map<Id, String> getTrackingNumbers(List<Shipment__c> shipments) {
        Map<Id, String> trackingById = new Map<Id, String>();
        for (Shipment__c s : [SELECT Id, Name FROM Shipment__c WHERE Id IN :shipments WITH SYSTEM_MODE]) {
            trackingById.put(s.Id, s.Name);
        }
        return trackingById;
    }

    /**
     * @return the guest user of the RutaCargo site (created with the site).
     */
    public static User getSiteGuestUser() {
        return [
            SELECT Id FROM User
            WHERE Profile.Name = :SITE_GUEST_PROFILE AND UserType = 'Guest' AND IsActive = true
            LIMIT 1
        ];
    }

    /**
     * Creates an internal owner with a role (portal accounts need one), the account,
     * its contact and a customer site user with the given permission set.
     * Runs DML as the owner to avoid mixed DML.
     * @return the customer site user
     */
    public static User createCustomerUser(String accountName, String lastName, String permissionSetName) {
        User owner = createAccountOwner(lastName);
        User customer;
        System.runAs(owner) {
            Account acct = buildCustomerAccount(accountName);
            acct.OwnerId = owner.Id;
            Database.insert(acct, AccessLevel.SYSTEM_MODE);
            Contact person = new Contact(AccountId = acct.Id, FirstName = 'Test', LastName = lastName,
                Email = lastName.toLowerCase() + '@example.com');
            Database.insert(person, AccessLevel.SYSTEM_MODE);
            Profile customerProfile = [SELECT Id FROM Profile WHERE Name = :CUSTOMER_PROFILE LIMIT 1];
            customer = new User(
                ProfileId = customerProfile.Id,
                ContactId = person.Id,
                FirstName = 'Test',
                LastName = lastName,
                Email = person.Email,
                Username = lastName.toLowerCase() + '.' + System.currentTimeMillis() + '@example.com.rutacargo.test',
                Alias = lastName.left(8),
                TimeZoneSidKey = 'America/Mexico_City',
                LocaleSidKey = 'en_US',
                EmailEncodingKey = 'UTF-8',
                LanguageLocaleKey = 'en_US'
            );
            Database.insert(customer, AccessLevel.SYSTEM_MODE);
            if (permissionSetName != null) {
                PermissionSet permSet = [SELECT Id FROM PermissionSet WHERE Name = :permissionSetName LIMIT 1];
                Database.insert(new PermissionSetAssignment(AssigneeId = customer.Id, PermissionSetId = permSet.Id), AccessLevel.SYSTEM_MODE);
            }
        }
        return customer;
    }

    /**
     * @return an active internal user with the RutaCargo Operations role.
     */
    public static User createAccountOwner(String suffix) {
        UserRole role = [SELECT Id FROM UserRole WHERE DeveloperName = 'RutaCargo_Operations' LIMIT 1];
        Profile adminProfile = [SELECT Id FROM Profile WHERE Name = 'System Administrator' LIMIT 1];
        User owner = new User(
            ProfileId = adminProfile.Id,
            UserRoleId = role.Id,
            FirstName = 'Owner',
            LastName = suffix,
            Email = 'owner.' + suffix.toLowerCase() + '@example.com',
            Username = 'owner.' + suffix.toLowerCase() + '.' + System.currentTimeMillis() + '@example.com.rutacargo.test',
            Alias = ('o' + suffix).left(8),
            TimeZoneSidKey = 'America/Mexico_City',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US'
        );
        System.runAs(new User(Id = UserInfo.getUserId())) {
            Database.insert(owner, AccessLevel.SYSTEM_MODE);
        }
        return owner;
    }

    /**
     * @return an internal API user with only the EntregaYa Integration permission set,
     * as the real EntregaYa integration user (Minimum Access profile, no other access).
     */
    public static User createIntegrationUser() {
        Profile minimum = [SELECT Id FROM Profile WHERE Name = 'Minimum Access - Salesforce' LIMIT 1];
        User integration = new User(
            ProfileId = minimum.Id,
            FirstName = 'EntregaYa',
            LastName = 'Integration',
            Email = 'entregaya.integration@example.com',
            Username = 'entregaya.' + System.currentTimeMillis() + '@example.com.rutacargo.test',
            Alias = 'eyint',
            TimeZoneSidKey = 'America/Mexico_City',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US'
        );
        System.runAs(new User(Id = UserInfo.getUserId())) {
            Database.insert(integration, AccessLevel.SYSTEM_MODE);
            PermissionSet permSet = [SELECT Id FROM PermissionSet WHERE Name = 'EntregaYa_Integration' LIMIT 1];
            Database.insert(new PermissionSetAssignment(AssigneeId = integration.Id, PermissionSetId = permSet.Id), AccessLevel.SYSTEM_MODE);
        }
        return integration;
    }
}
