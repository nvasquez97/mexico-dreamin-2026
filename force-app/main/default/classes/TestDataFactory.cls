@IsTest
public class TestDataFactory {
    public static Account account(String name) {
        Account a = new Account(Name = name, Customer_Type__c = 'Business', Credit_Risk__c = 'Low', Credit_Limit__c = 1000);
        insert a;
        return a;
    }

    public static Shipment__c shipment(Id accountId, String status, String postal) {
        Date est = ShipmentRules.today().addDays(3);
        Shipment__c s = new Shipment__c(
            Account__c = accountId, Status__c = status, Service_Type__c = 'Standard', Origin_City__c = 'Puebla',
            Destination_City__c = 'Mérida', Destination_Postal_Code__c = postal, Pickup_Postal_Code__c = '72000',
            Recipient_Name__c = 'Rita Recipient', Recipient_Address__c = 'Calle 1', Recipient_Phone__c = '9995551234',
            Recipient_Email__c = 'rita@example.com', Delivery_Instructions__c = 'Call first', Weight_Kg__c = 2,
            Declared_Value__c = 1000, Price__c = 200, Carrier_Cost__c = 120, Internal_Notes__c = 'SECRET NOTE',
            Estimated_Delivery__c = est, Original_Estimated_Delivery__c = est, Reschedule_Count__c = 0,
            Last_Location__c = 'Hub', Last_Update__c = Datetime.now().addHours(-2), Customer_Reference__c = 'REF-1'
        );
        insert s;
        return [SELECT Id, Name, Status__c, Estimated_Delivery__c, Destination_Postal_Code__c FROM Shipment__c WHERE Id = :s.Id];
    }

    /** A customer-community user whose contact belongs to the given account. */
    public static User customerUser(Account acc, String email) {
        User admin = [SELECT Id FROM User WHERE Id = :UserInfo.getUserId()];
        Contact c;
        System.runAs(admin) {
            UserRole r = new UserRole(Name = 'Test Owner Role ' + email);
            insert r;
            update new User(Id = admin.Id, UserRoleId = r.Id);
        }
        System.runAs(admin) {
            update new Account(Id = acc.Id, OwnerId = admin.Id);
            c = new Contact(AccountId = acc.Id, FirstName = 'Test', LastName = 'Customer', Email = email);
            insert c;
        }
        User u = new User(
            ContactId = c.Id, ProfileId = [SELECT Id FROM Profile WHERE Name = :AuthController.CUSTOMER_PROFILE].Id,
            FirstName = 'Test', LastName = 'Customer', Email = email, Username = email + '.rutacargo', Alias = 'tcust',
            CommunityNickname = 'tc' + String.valueOf(Math.abs(Crypto.getRandomInteger())), TimeZoneSidKey = 'America/Mexico_City',
            LocaleSidKey = 'es_MX', LanguageLocaleKey = 'en_US', EmailEncodingKey = 'UTF-8'
        );
        System.runAs(admin) {
            insert u;
        }
        return u;
    }

    /** A fresh internal user holding the given permission set (e.g. the integration or public-site user). */
    public static User userWith(String permissionSetName) {
        User u = new User(
            FirstName = 'T', LastName = 'User ' + permissionSetName, Email = 'tu@example.com',
            Username = 'tu' + String.valueOf(Math.abs(Crypto.getRandomLong())) + '@example.com.rutacargo',
            Alias = 'tuser', TimeZoneSidKey = 'America/Mexico_City', LocaleSidKey = 'en_US', LanguageLocaleKey = 'en_US',
            EmailEncodingKey = 'UTF-8', ProfileId = [SELECT Id FROM Profile WHERE Name = 'Standard User'].Id
        );
        System.runAs(new User(Id = UserInfo.getUserId())) {
            insert u;
            if (permissionSetName != null) {
                insert new PermissionSetAssignment(AssigneeId = u.Id,
                    PermissionSetId = [SELECT Id FROM PermissionSet WHERE Name = :permissionSetName].Id);
            }
        }
        return u;
    }

    public static Date nextBusinessDay(Integer minDaysAhead) {
        Date d = ShipmentRules.today().addDays(minDaysAhead);
        while (!ShipmentRules.isBusinessDay(d)) {
            d = d.addDays(1);
        }
        return d;
    }
}
