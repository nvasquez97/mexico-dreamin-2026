// Step 2 of 2: one site (customer) user per test contact. Separate transaction: users are setup
// objects and cannot be inserted in the same transaction as accounts/contacts (MIXED_DML_OPERATION).
// The password is random and printed once in the log line "TESTUSER ...".
Id profileId = [SELECT Id FROM Profile WHERE Name = 'RutaCargo Customer'].Id;
List<User> existing = [SELECT Id FROM User WHERE Username IN ('ana.lopez@example.com.rutacargo', 'marta.ruiz@example.com.rutacargo')];
if (!existing.isEmpty()) {
    System.debug('TESTUSER users already exist; leaving them (users cannot be deleted)');
    return;
}
List<User> users = new List<User>();
for (Contact c : [SELECT Id, FirstName, LastName, Email FROM Contact WHERE Email IN ('ana.lopez@example.com', 'marta.ruiz@example.com') ORDER BY Email]) {
    users.add(new User(
        ContactId = c.Id, ProfileId = profileId, FirstName = c.FirstName, LastName = c.LastName, Email = c.Email,
        Username = c.Email + '.rutacargo', Alias = (c.FirstName.left(1) + c.LastName).left(8),
        CommunityNickname = c.FirstName + c.LastName + 'RC', TimeZoneSidKey = 'America/Mexico_City', LocaleSidKey = 'es_MX',
        LanguageLocaleKey = 'en_US', EmailEncodingKey = 'UTF-8', IsActive = true
    ));
}
insert users;
String pwd = 'Rc' + String.valueOf(Math.abs(Crypto.getRandomLong())).left(10) + 'x';
for (User u : users) {
    System.setPassword(u.Id, pwd);
    System.debug('TESTUSER ' + u.Email + ' / ' + pwd);
}
