// RutaCargo seed, step 2 of 3 (data records). Idempotent: does nothing if the customers exist.
// Two business customers with one contact each and 120 shipments RC000001001..RC000001120
// across all statuses; at least 10 Delivered per customer with a proof id. All data is fictional.
RutaCargo_Settings__c settings = RutaCargo_Settings__c.getOrgDefaults();
if (settings.Account_Owner_Id__c == null) {
    settings.Account_Owner_Id__c = UserInfo.getUserId();
    upsert settings;
}
if ([SELECT COUNT() FROM Account WHERE Name IN ('Abarrotes Acme', 'Globex Farma')] > 0) {
    System.debug('SEED2 SKIPPED: customers already exist');
    return;
}
Account acme = new Account(Name = 'Abarrotes Acme', Customer_Type__c = 'Business', Credit_Risk__c = 'Low', Credit_Limit__c = 500000, Phone = '+52 55 5555 1001');
Account globex = new Account(Name = 'Globex Farma', Customer_Type__c = 'Business', Credit_Risk__c = 'High', Credit_Limit__c = 150000, Phone = '+52 81 5555 2002');
insert new List<Account>{ acme, globex };
insert new List<Contact>{
    new Contact(AccountId = acme.Id, FirstName = 'Ana', LastName = 'López', Email = 'ana.lopez@abarrotes-acme.example', Phone = '+52 55 5555 1010'),
    new Contact(AccountId = globex.Id, FirstName = 'Marta', LastName = 'Ruiz', Email = 'marta.ruiz@globex-farma.example', Phone = '+52 81 5555 2020')
};

List<String> cities = new List<String>{ 'Ciudad de México', 'Monterrey', 'Guadalajara', 'Puebla', 'Querétaro', 'Mérida', 'Tijuana', 'León', 'Toluca', 'Oaxaca' };
List<String> states = new List<String>{ 'CDMX', 'NL', 'JAL', 'PUE', 'QRO', 'YUC', 'BC', 'GTO', 'MEX', 'OAX' };
List<String> postalCodes = new List<String>{ '06600', '64000', '44100', '72000', '76000', '97000', '22000', '37000', '50000', '68000' };
List<String> streets = new List<String>{ 'Av. Reforma', 'Calle Hidalgo', 'Av. Juárez', 'Calle Morelos', 'Av. Insurgentes', 'Calle Allende', 'Av. Revolución', 'Calle Zaragoza', 'Calle Madero', 'Av. Universidad' };
List<String> firstNames = new List<String>{ 'Laura', 'Pedro', 'Sofía', 'Diego', 'Valeria', 'Jorge', 'Camila', 'Luis', 'Fernanda', 'Miguel', 'Daniela', 'Ricardo' };
List<String> lastNames = new List<String>{ 'García', 'Hernández', 'Martínez', 'Rodríguez', 'Pérez', 'Sánchez', 'Ramírez', 'Torres', 'Flores', 'Vargas', 'Castillo', 'Morales' };
List<String> contents = new List<String>{ 'Abarrotes surtidos', 'Medicamentos', 'Documentos', 'Refacciones', 'Libros', 'Ropa', 'Electrónicos', 'Cosméticos' };
// 60 statuses per customer: 14 Delivered, 12 In transit, 10 Picked up, 8 Out for delivery, 10 Requested, 6 Exception.
List<String> statusPlan = new List<String>();
Map<String, Integer> counts = new Map<String, Integer>{ 'Delivered' => 14, 'In transit' => 12, 'Picked up' => 10, 'Out for delivery' => 8, 'Requested' => 10, 'Exception' => 6 };
for (String status : counts.keySet()) {
    for (Integer i = 0; i < counts.get(status); i++) {
        statusPlan.add(status);
    }
}
Date today = BusinessCalendar.todayInMexicoCity();
List<Shipment__c> shipments = new List<Shipment__c>();
List<Account> customers = new List<Account>{ acme, globex };
for (Integer c = 0; c < customers.size(); c++) {
    for (Integer i = 0; i < 60; i++) {
        Integer n = c * 60 + i;
        String status = statusPlan[Math.mod(i * 7, 60)];
        Integer origin = Math.mod(n, 10);
        Integer destination = Math.mod(n * 3 + 1, 10);
        if (destination == origin) {
            destination = Math.mod(destination + 1, 10);
        }
        String service = Math.mod(n, 3) == 0 ? 'Express' : 'Standard';
        Decimal weight = 1 + Math.mod(n * 7, 29) + 0.5;
        Decimal declared = 500 + Math.mod(n * 1373, 30000);
        Decimal price = PricingService.calculatePrice(service, weight, declared);
        Date pickup = status == 'Requested'
            ? BusinessCalendar.addBusinessDays(today, 1 + Math.mod(n, 5))
            : today.addDays(-(3 + Math.mod(n, 20)));
        Date estimated = BusinessCalendar.addBusinessDays(pickup, PricingService.getTransitBusinessDays(service));
        Datetime lastUpdate = status == 'Requested' ? null : Datetime.newInstance(pickup.addDays(1), Time.newInstance(9 + Math.mod(n, 8), 15, 0, 0));
        Shipment__c s = new Shipment__c(
            Account__c = customers[c].Id,
            Status__c = status,
            Service_Type__c = service,
            Customer_Reference__c = (c == 0 ? 'ACME-' : 'GLX-') + String.valueOf(2026000 + i),
            Pickup_Address__c = streets[origin] + ' ' + (100 + n) + ', Col. Centro',
            Origin_City__c = cities[origin],
            Pickup_Postal_Code__c = postalCodes[origin],
            Pickup_Date__c = pickup,
            Recipient_Name__c = firstNames[Math.mod(n, 12)] + ' ' + lastNames[Math.mod(n * 5, 12)],
            Recipient_Address__c = streets[destination] + ' ' + (200 + n) + ', Col. Centro',
            Destination_City__c = cities[destination],
            Destination_Postal_Code__c = postalCodes[destination],
            Recipient_Phone__c = '+52 55 5555 ' + String.valueOf(3000 + n),
            Recipient_Email__c = 'destinatario' + n + '@example.com',
            Delivery_Instructions__c = Math.mod(n, 4) == 0 ? 'Dejar con el vigilante' : null,
            Package_Description__c = contents[Math.mod(n, 8)],
            Weight_Kg__c = weight,
            Declared_Value__c = declared,
            Price__c = price,
            Carrier_Cost__c = (price * 0.55).setScale(2),
            Internal_Notes__c = 'Ruta ' + states[origin] + '-' + states[destination] + (Math.mod(n, 5) == 0 ? '. Cliente prefiere recolección matutina.' : '.'),
            Estimated_Delivery__c = estimated,
            Original_Estimated_Delivery__c = estimated,
            Reschedule_Count__c = 0,
            Last_Location__c = status == 'Requested' ? null : (status == 'Delivered' || status == 'Out for delivery' ? cities[destination] : cities[origin]) + ', ' + (status == 'Delivered' || status == 'Out for delivery' ? states[destination] : states[origin]),
            Last_Update__c = lastUpdate
        );
        if (status == 'Delivered') {
            s.Delivered_At__c = lastUpdate.addHours(3);
            s.Last_Update__c = s.Delivered_At__c;
            s.Proof_Id__c = 'PRF-' + String.valueOf(88000 + n);
        }
        shipments.add(s);
    }
}
insert shipments;
System.debug('SEED2 OK shipments: ' + shipments.size());
