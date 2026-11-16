// Creates the two site users (Ana Lopez, Marta Ruiz) for the loaded customers and sets a random password for each.
// Passwords are generated at run time and printed once in the debug log; they are never stored in the repo.
// Requires the sender address of the site to be verified (System.setPassword depends on it) and the running
// user to hold the RutaCargo Customer Owner role (scripts/setup-org.sh does both checks/assignments except verification).
Profile profile = [SELECT Id FROM Profile WHERE Name = 'RutaCargo Customer' LIMIT 1];
List<Contact> contacts = [SELECT Id, FirstName, LastName, Email FROM Contact WHERE Email IN ('ana.lopez@acme.example.com', 'marta.ruiz@globex.example.com')];
List<User> users = new List<User>();
for (Contact contact : contacts) {
    String username = contact.Email + CustomerService.USERNAME_SUFFIX;
    if ([SELECT COUNT() FROM User WHERE Username = :username] > 0) {
        System.debug('User already exists: ' + username);
        continue;
    }
    users.add(new User(
        Username = username, Email = contact.Email, FirstName = contact.FirstName, LastName = contact.LastName,
        Alias = (contact.FirstName.left(1) + contact.LastName).left(8), CommunityNickname = 'seed' + contact.LastName.toLowerCase(),
        ProfileId = profile.Id, ContactId = contact.Id, TimeZoneSidKey = 'America/Mexico_City', LocaleSidKey = 'en_US',
        EmailEncodingKey = 'UTF-8', LanguageLocaleKey = 'en_US'
    ));
}
insert users;
for (User user : users) {
    String password = EncodingUtil.convertToHex(Crypto.generateAesKey(128)).left(14) + 'aA1';
    System.setPassword(user.Id, password);
    System.debug('SITE USER ' + user.Username + ' PASSWORD ' + password);
}
