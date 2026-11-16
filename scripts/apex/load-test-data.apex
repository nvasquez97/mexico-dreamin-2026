// Loads the RutaCargo development data: 2 customers (Account + Contact) and 120 shipments.
// All names, addresses and phone numbers are fictional. Idempotent: does nothing if the data already exists.
// Run through scripts/setup-org.sh (needs the RutaCargo_Support_Agent permission set for field access).
if ([SELECT COUNT() FROM Account WHERE Name = 'Abarrotes Acme'] > 0) {
    System.debug('Test data already loaded; nothing to do.');
    return;
}

List<String> statuses = new List<String>{ 'Requested', 'Picked up', 'In transit', 'Out for delivery', 'Delivered', 'Exception' };
List<String> cities = new List<String>{ 'Monterrey', 'Guadalajara', 'Ciudad de Mexico', 'Puebla', 'Queretaro', 'Merida', 'Leon', 'Tijuana', 'Toluca', 'Cancun' };
List<String> postals = new List<String>{ '64000', '44100', '06600', '72000', '76000', '97000', '37000', '22000', '50000', '77500' };
List<String> streets = new List<String>{ 'Av. Hidalgo', 'Calle Morelos', 'Av. Juarez', 'Calle Reforma', 'Av. Insurgentes', 'Calle 5 de Mayo', 'Av. Universidad', 'Calle Allende' };
List<String> recipients = new List<String>{
    'Luis Perez', 'Carmen Soto', 'Jorge Herrera', 'Sofia Mendez', 'Ricardo Vega', 'Paula Castillo', 'Diego Navarro', 'Valeria Rios',
    'Andres Molina', 'Lucia Ortega', 'Hector Salas', 'Monica Fuentes'
};
List<String> packages = new List<String>{ 'Books', 'Spare parts', 'Clothing', 'Medical supplies', 'Electronics', 'Kitchenware', 'Toys', 'Office supplies' };
List<String> locations = new List<String>{ 'Ciudad de Mexico, CDMX', 'Queretaro, QRO', 'Monterrey, NL', 'Guadalajara, JAL', 'Puebla, PUE', 'Toluca, MEX' };

Account acme = new Account(Name = 'Abarrotes Acme', Customer_Type__c = 'Business', Credit_Risk__c = 'Low', Credit_Limit__c = 500000, Phone = '5555010001');
Account globex = new Account(Name = 'Globex Farma', Customer_Type__c = 'Business', Credit_Risk__c = 'High', Credit_Limit__c = 150000, Phone = '5555010002');
insert new List<Account>{ acme, globex };
insert new List<Contact>{
    new Contact(AccountId = acme.Id, FirstName = 'Ana', LastName = 'Lopez', Email = 'ana.lopez@acme.example.com', Phone = '5555010011'),
    new Contact(AccountId = globex.Id, FirstName = 'Marta', LastName = 'Ruiz', Email = 'marta.ruiz@globex.example.com', Phone = '5555010012')
};

Date today = ShipmentRules.today();
List<Shipment__c> shipments = new List<Shipment__c>();
// Acme first (RC000001001..1060), then Globex (RC000001061..1120): the auto-number follows list order.
for (Integer c = 0; c < 2; c++) {
    Account owner = c == 0 ? acme : globex;
    for (Integer i = 0; i < 60; i++) {
        Integer n = c * 60 + i;
        String status = statuses[Math.mod(i, 6)];
        String service = Math.mod(i, 3) == 0 ? 'Express' : 'Standard';
        Decimal weight = 1 + Math.mod(i * 7, 25);
        Decimal declared = 500 + Math.mod(i * 913, 40000);
        Decimal price = ShipmentRules.calculatePrice(service, weight, declared);
        Integer destination = Math.mod(n * 3 + 1, cities.size());
        Integer origin = Math.mod(n, cities.size());
        Date pickup = today.addDays(-Math.mod(i, 9));
        Date estimate = pickup.addDays(service == 'Express' ? 2 : 5);
        if (status == 'Picked up' || status == 'In transit') {
            estimate = today.addDays(2 + Math.mod(i, 4)); // still in the future so recipients can try rescheduling
        }
        Shipment__c s = new Shipment__c(
            Account__c = owner.Id,
            Status__c = status,
            Service_Type__c = service,
            Customer_Reference__c = (c == 0 ? 'ACME-' : 'GLX-') + String.valueOf(2000 + i),
            Pickup_Address__c = streets[Math.mod(n, streets.size())] + ' ' + (100 + n) + ', ' + cities[origin],
            Pickup_Postal_Code__c = postals[origin],
            Pickup_Date__c = pickup,
            Origin_City__c = cities[origin],
            Destination_City__c = cities[destination],
            Recipient_Name__c = recipients[Math.mod(n, recipients.size())],
            Recipient_Address__c = streets[Math.mod(n + 3, streets.size())] + ' ' + (10 + n * 2) + ', ' + cities[destination],
            Destination_Postal_Code__c = postals[destination],
            Recipient_Phone__c = '55' + String.valueOf(10000000 + n * 137),
            Recipient_Email__c = 'recipient' + n + '@example.com',
            Delivery_Instructions__c = Math.mod(n, 2) == 0 ? 'Leave with the doorman' : 'Call before arriving',
            Package_Description__c = packages[Math.mod(n, packages.size())],
            Weight_Kg__c = weight,
            Declared_Value__c = declared,
            Price__c = price,
            Carrier_Cost__c = (price * 0.62).setScale(2),
            Internal_Notes__c = 'Seed data. Route reviewed by operations.',
            Estimated_Delivery__c = estimate,
            Original_Estimated_Delivery__c = estimate,
            Reschedule_Count__c = 0
        );
        if (status != 'Requested') {
            s.Last_Location__c = locations[Math.mod(n, locations.size())];
            s.Last_Update__c = Datetime.now().addHours(-(1 + Math.mod(n, 40)));
        }
        if (status == 'Delivered') {
            s.Delivered_At__c = s.Last_Update__c;
            s.Proof_Id__c = 'PRF-' + String.valueOf(88000 + n);
            s.Estimated_Delivery__c = today.addDays(-Math.mod(i, 5));
            s.Original_Estimated_Delivery__c = s.Estimated_Delivery__c;
        }
        shipments.add(s);
    }
}
insert shipments;
System.debug('Loaded 2 customers and ' + shipments.size() + ' shipments.');
