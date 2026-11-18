// Site users of the two seeded customers (odd/tasks/req-005-customer-signup.md,
// S5, AC-005.8, foundation A4). Users and permission set assignments are data,
// not metadata, so they are created here, not in force-app. Run it with
// scripts/setup/seed-customer-users.sh <org-alias>, which reads the result back.
//
// For Ana López (ana.lopez@example.com, Abarrotes Acme) and Marta Ruiz
// (marta.ruiz@example.com, Globex Farma), in one transaction:
//   1. one user with the profile "RutaCargo Customer", linked to the seeded
//      Contact, created when the Contact has no user: username = normalized
//      email + "." + the 18-character org Id in lower case (F1);
//      CommunityNickname = email local part (30 at most) + "-" + 6 random
//      characters; Alias = the first 4 letters of the local part + 4 random
//      characters; time zone America/Mexico_City; locale es_MX, language en_US;
//      an inactive user of that profile and username is activated again;
//   2. the permission set RutaCargo_Customer, assigned when missing.
// It never sets, prints or stores a password: the owner resets it in Setup (F5).
// Idempotent. It refuses an org that is not a sandbox or scratch org, and a
// Contact whose user has another profile or another username (the owner
// decides). Uses 2 of the 5 Customer Community licenses.
final String PROFILE_NAME = 'RutaCargo Customer';
final String PERMISSION_SET = 'RutaCargo_Customer';
final String TIME_ZONE = 'America/Mexico_City';
// Normalized email => seeded Account name.
final Map<String, String> CUSTOMERS = new Map<String, String>{
    'ana.lopez@example.com' => 'Abarrotes Acme',
    'marta.ruiz@example.com' => 'Globex Farma'
};

Organization org = [SELECT Id, IsSandbox FROM Organization LIMIT 1];
if (!org.IsSandbox) {
    throw new IllegalArgumentException('seed-customer-users: refused, the org is not a sandbox or scratch org');
}
String usernameSuffix = '.' + String.valueOf(org.Id).toLowerCase();

List<Profile> profiles = [SELECT Id FROM Profile WHERE Name = :PROFILE_NAME LIMIT 1];
List<PermissionSet> permissionSets = [
    SELECT Id FROM PermissionSet WHERE Name = :PERMISSION_SET AND NamespacePrefix = null LIMIT 1
];
if (profiles.isEmpty() || permissionSets.isEmpty()) {
    throw new IllegalArgumentException('seed-customer-users: profile ' + PROFILE_NAME + ' or permission set '
        + PERMISSION_SET + ' not found; deploy them first (DEPLOY-ORDER.md)');
}

// One seeded Contact per email, on its seeded Account, whose owner has a role.
Map<String, Contact> contactByEmail = new Map<String, Contact>();
for (Contact c : [
    SELECT Id, FirstName, LastName, Email, Account.Name, Account.Owner.UserRoleId
    FROM Contact
    WHERE Email IN :CUSTOMERS.keySet() AND Account.Name IN :CUSTOMERS.values()
]) {
    String email = c.Email.trim().toLowerCase();
    if (CUSTOMERS.get(email) != c.Account.Name) {
        continue;
    }
    if (contactByEmail.containsKey(email)) {
        throw new IllegalArgumentException('seed-customer-users: more than one seeded Contact for ' + email);
    }
    contactByEmail.put(email, c);
}
for (String email : CUSTOMERS.keySet()) {
    Contact c = contactByEmail.get(email);
    if (c == null) {
        throw new IllegalArgumentException('seed-customer-users: seeded Contact ' + email + ' of '
            + CUSTOMERS.get(email) + ' not found; run the seed first');
    }
    if (c.Account.Owner.UserRoleId == null) {
        throw new IllegalArgumentException('seed-customer-users: the owner of ' + c.Account.Name
            + ' has no role; run scripts/setup/customer-owner.sh first');
    }
}

Map<Id, User> userByContact = new Map<Id, User>();
for (User u : [
    SELECT Id, ContactId, ProfileId, Username, IsActive
    FROM User
    WHERE ContactId IN :new Map<Id, Contact>(contactByEmail.values()).keySet()
]) {
    if (userByContact.containsKey(u.ContactId)) {
        throw new IllegalArgumentException('seed-customer-users: refused, a seeded Contact has more than one user');
    }
    userByContact.put(u.ContactId, u);
}

// Random lower-case hexadecimal characters for the nickname and the alias.
String randomHex = EncodingUtil.convertToHex(Crypto.generateAesKey(128));
Integer randomOffset = 0;
List<User> toInsert = new List<User>();
List<User> toActivate = new List<User>();
for (String email : CUSTOMERS.keySet()) {
    Contact c = contactByEmail.get(email);
    String username = email + usernameSuffix;
    User existing = userByContact.get(c.Id);
    if (existing != null) {
        if (existing.ProfileId != profiles[0].Id || existing.Username != username) {
            throw new IllegalArgumentException('seed-customer-users: refused, the user of ' + email
                + ' has another profile or username; the owner decides');
        }
        Boolean wasInactive = !existing.IsActive;
        if (wasInactive) {
            existing.IsActive = true;
            toActivate.add(existing);
        }
        System.debug(LoggingLevel.INFO, 'seed-customer-users: ' + username + ' already exists'
            + (wasInactive ? ', activated again' : ''));
        continue;
    }
    String localPart = email.substringBefore('@');
    String letters = localPart.replaceAll('[^a-z]', '');
    String nickname = localPart.left(30) + '-' + randomHex.substring(randomOffset, randomOffset + 6);
    String alias = letters.left(4) + randomHex.substring(randomOffset + 6, randomOffset + 10);
    randomOffset += 10;
    toInsert.add(new User(
        Username = username,
        Email = email,
        FirstName = c.FirstName,
        LastName = c.LastName,
        ContactId = c.Id,
        ProfileId = profiles[0].Id,
        CommunityNickname = nickname,
        Alias = alias.left(8),
        TimeZoneSidKey = TIME_ZONE,
        LocaleSidKey = 'es_MX',
        LanguageLocaleKey = 'en_US',
        EmailEncodingKey = 'UTF-8'
    ));
}
if (!toActivate.isEmpty()) {
    update toActivate;
}
if (!toInsert.isEmpty()) {
    insert toInsert;
    for (User u : toInsert) {
        System.debug(LoggingLevel.INFO, 'seed-customer-users: ' + u.Username + ' created');
    }
}

// The permission set, on every seeded customer user that lacks it.
Set<Id> userIds = new Set<Id>();
for (User u : [SELECT Id FROM User WHERE ContactId IN :new Map<Id, Contact>(contactByEmail.values()).keySet()]) {
    userIds.add(u.Id);
}
for (PermissionSetAssignment psa : [
    SELECT AssigneeId FROM PermissionSetAssignment
    WHERE PermissionSetId = :permissionSets[0].Id AND AssigneeId IN :userIds
]) {
    userIds.remove(psa.AssigneeId);
}
List<PermissionSetAssignment> assignments = new List<PermissionSetAssignment>();
for (Id userId : userIds) {
    assignments.add(new PermissionSetAssignment(AssigneeId = userId, PermissionSetId = permissionSets[0].Id));
}
if (!assignments.isEmpty()) {
    insert assignments;
}
System.debug(LoggingLevel.INFO, 'seed-customer-users: permission set ' + PERMISSION_SET + ' assigned to '
    + assignments.size() + ' user(s), already on ' + (contactByEmail.size() - assignments.size()));
