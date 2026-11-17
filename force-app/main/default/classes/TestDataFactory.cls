/**
 * @description Shared test data builders for RutaCargo. Builders return UNSAVED
 *              records with every required field set, so each test decides when
 *              to insert and which fields to override.
 */
@IsTest
public with sharing class TestDataFactory {

    public static final String DEFAULT_ACCOUNT_NAME = 'Test Customer';
    public static final String PLATFORM_PROFILE_NAME = 'Standard Platform User';

    // ─── Accounts (customers) ─────────────────────────────────────────────

    public static Account newCustomerAccount(String name) {
        return new Account(
            Name = name,
            Customer_Type__c = 'Business',
            Credit_Limit__c = 100000,
            Credit_Risk__c = 'Low'
        );
    }

    public static Account newCustomerAccount() {
        return newCustomerAccount(DEFAULT_ACCOUNT_NAME);
    }

    // ─── Shipments ────────────────────────────────────────────────────────

    /**
     * @description Unsaved shipment for the given customer. Status__c is left
     *              empty on purpose so the field default applies on insert.
     */
    public static Shipment__c newShipment(Id accountId) {
        return new Shipment__c(
            Account__c = accountId,
            Service_Type__c = 'Standard',
            Pickup_Address__c = 'Av. Reforma 100, Col. Juarez',
            Pickup_Postal_Code__c = '06600',
            Pickup_Date__c = Date.newInstance(2026, 12, 1),
            Origin_City__c = 'Ciudad de Mexico',
            Destination_City__c = 'Guadalajara',
            Recipient_Name__c = 'Test Recipient',
            Recipient_Address__c = 'Av. Vallarta 200, Col. Americana',
            Destination_Postal_Code__c = '44160',
            Recipient_Phone__c = '+52 33 0000 0000',
            Recipient_Email__c = 'recipient@example.com',
            Package_Description__c = 'Test package',
            Weight_Kg__c = 1.5
        );
    }

    public static List<Shipment__c> newShipments(Id accountId, Integer count) {
        List<Shipment__c> shipments = new List<Shipment__c>();
        for (Integer i = 0; i < count; i++) {
            shipments.add(newShipment(accountId));
        }
        return shipments;
    }

    // ─── Users ────────────────────────────────────────────────────────────

    /**
     * @description Unsaved internal user with the given profile. The username is
     *              made unique with the org id and the given key.
     * @param profileId the profile of the user
     * @param uniqueKey a short key (letters and digits) that makes the user unique in the test
     * @return the unsaved user
     */
    public static User newUser(Id profileId, String uniqueKey) {
        return new User(
            ProfileId = profileId,
            LastName = 'Test ' + uniqueKey,
            Alias = uniqueKey.left(8),
            Email = uniqueKey + '@example.com',
            Username = uniqueKey + '.' + UserInfo.getOrganizationId() + '@example.com.rutacargo',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            TimeZoneSidKey = 'America/Mexico_City'
        );
    }

    /**
     * @description Unsaved Standard Platform Users (Salesforce Platform license),
     *              one per key. The org has 3 Salesforce Platform licenses, so a
     *              test must not insert more than 3 of them.
     * @param uniqueKeys short keys (letters and digits), one per user
     * @return the unsaved users, in the order of the keys
     */
    public static List<User> newPlatformUsers(List<String> uniqueKeys) {
        Id profileId = [SELECT Id FROM Profile WHERE Name = :PLATFORM_PROFILE_NAME WITH USER_MODE LIMIT 1].Id;
        List<User> users = new List<User>();
        for (String uniqueKey : uniqueKeys) {
            users.add(newUser(profileId, uniqueKey));
        }
        return users;
    }

    /**
     * @description Unsaved permission set assignments of one permission set to
     *              each given user.
     */
    public static List<PermissionSetAssignment> newPermissionSetAssignments(Id permissionSetId, List<User> users) {
        List<PermissionSetAssignment> assignments = new List<PermissionSetAssignment>();
        for (User member : users) {
            assignments.add(new PermissionSetAssignment(PermissionSetId = permissionSetId, AssigneeId = member.Id));
        }
        return assignments;
    }

    /**
     * @description Unsaved manual shares of each shipment with one group. Tests
     *              use them to mirror a criteria-based sharing rule, which the
     *              platform does not evaluate in Apex tests (assumption A10).
     */
    public static List<Shipment__Share> newShipmentGroupShares(List<Shipment__c> shipments, Id groupId, String accessLevel) {
        List<Shipment__Share> shares = new List<Shipment__Share>();
        for (Shipment__c shipment : shipments) {
            shares.add(new Shipment__Share(
                ParentId = shipment.Id,
                UserOrGroupId = groupId,
                AccessLevel = accessLevel,
                RowCause = Schema.Shipment__Share.RowCause.Manual
            ));
        }
        return shares;
    }

    /**
     * @description Unsaved manual shares of each account with one group, with no
     *              access to the account's opportunities and cases (contacts
     *              follow the account: Controlled by Parent). Mirrors a
     *              criteria-based Account sharing rule in tests (assumption A10).
     */
    public static List<AccountShare> newAccountGroupShares(List<Account> accounts, Id groupId, String accessLevel) {
        List<AccountShare> shares = new List<AccountShare>();
        for (Account customer : accounts) {
            shares.add(new AccountShare(
                AccountId = customer.Id,
                UserOrGroupId = groupId,
                AccountAccessLevel = accessLevel,
                OpportunityAccessLevel = 'None',
                CaseAccessLevel = 'None'
            ));
        }
        return shares;
    }

    /**
     * @description Unsaved memberships of each given user in one public group.
     */
    public static List<GroupMember> newGroupMembers(Id groupId, List<User> users) {
        List<GroupMember> members = new List<GroupMember>();
        for (User member : users) {
            members.add(new GroupMember(GroupId = groupId, UserOrGroupId = member.Id));
        }
        return members;
    }
}
