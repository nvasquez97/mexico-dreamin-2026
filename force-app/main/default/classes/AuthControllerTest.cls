@IsTest
private class AuthControllerTest {
    private class StubCreator implements AuthController.UserCreator {
        Boolean loginOk = true;
        public Id createUser(User u, Id accountId, String password) {
            Contact c = new Contact(AccountId = accountId, FirstName = u.FirstName, LastName = u.LastName, Email = u.Email);
            insert c;
            u.ContactId = c.Id;
            System.runAs(new User(Id = UserInfo.getUserId())) {
                insert u;
            }
            return u.Id;
        }
        public String login(String username, String password, String startUrl) {
            return loginOk ? 'LOGIN:' + username + ':' + startUrl : null;
        }
        public Boolean forgotPassword(String username) {
            return true;
        }
    }

    private static Map<String, Object> form(String email, String pwd) {
        return new Map<String, Object>{
            'customerType' => 'Business', 'accountName' => 'Nueva SA', 'firstName' => 'Nora', 'lastName' => 'Nueva',
            'email' => email, 'phone' => '5551112222', 'password' => pwd
        };
    }

    private static void expectError(Map<String, Object> f, String fragment) {
        try {
            AuthController.signUp(f, '/');
            System.assert(false, 'expected an error containing: ' + fragment);
        } catch (AuraHandledException e) {
            System.assert(e.getMessage().contains(fragment), e.getMessage());
        }
    }

    // AC-005.1, AC-005.2, AC-005.3
    @IsTest
    static void signUpCreatesCustomerAndRejectsDuplicates() {
        AuthController.creator = new StubCreator();
        System.runAs(new User(Id = UserInfo.getUserId())) {
            String url = AuthController.signUp(form('Nora@Example.com', 'abcdefgh12'), '/rutacargo/request');
            System.assertEquals('LOGIN:nora@example.com.rutacargo:/rutacargo/request', url);
            Account a = [SELECT Name, Customer_Type__c, (SELECT Email, LastName FROM Contacts) FROM Account WHERE Name = 'Nueva SA'];
            System.assertEquals('Business', a.Customer_Type__c);
            System.assertEquals(1, a.Contacts.size());
            expectError(form('nora@example.com', 'abcdefgh12'), 'already registered');
            System.assertEquals(1, [SELECT COUNT() FROM Account WHERE Name = 'Nueva SA'], 'no orphan account');
        }
    }

    // AC-005.1, AC-005.4
    @IsTest
    static void signUpValidation() {
        AuthController.creator = new StubCreator();
        expectError(form('a@example.com', 'short1'), 'at least 10');
        expectError(form('a@example.com', 'onlyletterss'), 'letters and numbers');
        expectError(form('not-an-email', 'abcdefgh12'), 'valid email');
        Map<String, Object> f = form('a@example.com', 'abcdefgh12'); f.put('customerType', 'Other'); expectError(f, 'individual or a business');
        f = form('a@example.com', 'abcdefgh12'); f.put('lastName', ''); expectError(f, 'Complete all');
        try {
            AuthController.signUp(null, '/');
            System.assert(false, 'expected an error');
        } catch (AuraHandledException e) {
            System.assert(e.getMessage().contains('Complete'));
        }
    }

    // AC-005.5, AC-005.6
    @IsTest
    static void loginAndPasswordReset() {
        StubCreator stub = new StubCreator();
        AuthController.creator = stub;
        System.assert(AuthController.login('x@example.com', 'pw', 'https://evil.example/').startsWith('LOGIN:x@example.com.rutacargo:/'), 'start URL must be site-relative');
        System.assertEquals('/a/b', AuthController.safeStartUrl('/a/b'));
        System.assertEquals('/', AuthController.safeStartUrl('//evil.example'));
        System.assertEquals('/', AuthController.safeStartUrl(null));
        stub.loginOk = false;
        try {
            AuthController.login('x@example.com', 'bad', '/');
            System.assert(false, 'expected an error');
        } catch (AuraHandledException e) {
            System.assertEquals('Incorrect email or password.', e.getMessage());
        }
        AuthController.forgotPassword('x@example.com'); // same answer for unknown emails
        try {
            AuthController.forgotPassword('nope');
            System.assert(false, 'expected an error');
        } catch (AuraHandledException e) {
            System.assert(e.getMessage().contains('valid email'));
        }
    }
}
