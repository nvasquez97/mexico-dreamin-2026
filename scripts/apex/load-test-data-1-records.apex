// Step 1 of 2: customers, contacts and 120 shipments (fictional data). Run via scripts/load-test-data.sh.
// Tracking numbers are an auto-number starting at RC000001001, so on a FRESH org the 120 shipments are
// RC000001001..RC000001120 (Abarrotes Acme = first 60, Globex Farma = last 60). Auto-numbers are never
// reused, so do NOT run Apex tests that insert shipments before loading this data.

// Re-runnable: customers/contacts are kept (their site users cannot be deleted); shipments are replaced.
List<Account> accounts = [SELECT Id, Name FROM Account WHERE Name IN ('Abarrotes Acme', 'Globex Farma') ORDER BY Name];
delete [SELECT Id FROM Shipment__c WHERE Account__c IN :accounts];
if (accounts.isEmpty()) {
    accounts = new List<Account>{
        new Account(Name = 'Abarrotes Acme', Customer_Type__c = 'Business', Credit_Risk__c = 'Low', Credit_Limit__c = 500000, Phone = '5555500101'),
        new Account(Name = 'Globex Farma', Customer_Type__c = 'Business', Credit_Risk__c = 'High', Credit_Limit__c = 150000, Phone = '5555500202')
    };
    insert accounts;
    insert new List<Contact>{
        new Contact(AccountId = accounts[0].Id, FirstName = 'Ana', LastName = 'López', Email = 'ana.lopez@example.com', Phone = '5555500101'),
        new Contact(AccountId = accounts[1].Id, FirstName = 'Marta', LastName = 'Ruiz', Email = 'marta.ruiz@example.com', Phone = '5555500202')
    };
}

// city, postal code, street
List<List<String>> places = new List<List<String>>{
    new List<String>{ 'Ciudad de México', '06600', 'Calle Londres 45, Col. Juárez' },
    new List<String>{ 'Guadalajara', '44100', 'Av. Hidalgo 210, Col. Centro' },
    new List<String>{ 'Monterrey', '64000', 'Calle Zaragoza 880, Col. Centro' },
    new List<String>{ 'Puebla', '72000', 'Av. Reforma 305, Col. Centro' },
    new List<String>{ 'Querétaro', '76000', 'Calle Corregidora 17, Col. Centro' },
    new List<String>{ 'Mérida', '97000', 'Calle 60 No. 412, Col. Centro' },
    new List<String>{ 'León', '37000', 'Blvd. Adolfo López Mateos 1200' },
    new List<String>{ 'Tijuana', '22000', 'Av. Revolución 1450, Zona Centro' }
};
List<String> firstNames = new List<String>{ 'Lucía', 'Carlos', 'Fernanda', 'Jorge', 'Daniela', 'Miguel', 'Valeria', 'Ricardo', 'Paola', 'Andrés' };
List<String> lastNames = new List<String>{ 'Hernández', 'García', 'Martínez', 'Rodríguez', 'Pérez', 'Sánchez', 'Ramírez', 'Torres', 'Flores', 'Vargas' };
List<String> contents = new List<String>{ 'Medicamentos de venta libre', 'Abarrotes envasados', 'Material de oficina', 'Refacciones', 'Ropa y textiles', 'Artículos de limpieza', 'Libros', 'Electrónicos pequeños' };
List<String> notes = new List<String>{ 'Cliente solicita factura al entregar.', 'Revisar embalaje: frágil.', 'Ruta consolidada con otro envío del mismo cliente.', 'Sin incidencias.', 'Domicilio de difícil acceso, avisar al chofer.' };

// Status mix per customer (60): 8 + 8 + 12 + 8 + 20 + 4
List<String> statusPlan = new List<String>();
for (Integer i = 0; i < 8; i++) { statusPlan.add('Requested'); }
for (Integer i = 0; i < 8; i++) { statusPlan.add('Picked up'); }
for (Integer i = 0; i < 12; i++) { statusPlan.add('In transit'); }
for (Integer i = 0; i < 8; i++) { statusPlan.add('Out for delivery'); }
for (Integer i = 0; i < 20; i++) { statusPlan.add('Delivered'); }
for (Integer i = 0; i < 4; i++) { statusPlan.add('Exception'); }

Date today = ShipmentRules.today();
List<Shipment__c> shipments = new List<Shipment__c>();
for (Integer a = 0; a < 2; a++) {
    String prefix = a == 0 ? 'ACME-PO-' : 'GLX-ORD-';
    for (Integer n = 0; n < 60; n++) {
        Integer k = a * 60 + n;
        String status = statusPlan[Math.mod(n * 7, 60)]; // deterministic shuffle (7 is coprime with 60)
        List<String> src = places[Math.mod(k, 8)];
        List<String> dst = places[Math.mod(k * 3 + 1, 8)];
        String service = Math.mod(k, 3) == 0 ? 'Express' : 'Standard';
        Decimal weight = 0.5 + Math.mod(k * 13, 49) / 2.0;
        Decimal declared = 200 + Math.mod(k * 937, 400) * 100;
        Decimal price = ShipmentPricing.calculate(service, weight, declared);

        Shipment__c s = new Shipment__c(
            Account__c = accounts[a].Id,
            Customer_Reference__c = Math.mod(k, 4) == 3 ? null : prefix + String.valueOf(1000 + n),
            Status__c = status,
            Service_Type__c = service,
            Pickup_Address__c = src[2],
            Pickup_Postal_Code__c = src[1],
            Origin_City__c = src[0],
            Destination_City__c = dst[0],
            Recipient_Name__c = firstNames[Math.mod(k, 10)] + ' ' + lastNames[Math.mod(k * 7 + 3, 10)],
            Recipient_Address__c = dst[2] + ', ' + dst[0],
            Destination_Postal_Code__c = dst[1],
            Recipient_Phone__c = '55' + String.valueOf(55500000 + k * 37),
            Recipient_Email__c = 'recipient' + (k + 1) + '@example.com',
            Delivery_Instructions__c = Math.mod(k, 3) == 0 ? 'Entregar en recepción, horario de 9 a 17 h.' : (Math.mod(k, 3) == 1 ? 'Llamar al llegar.' : null),
            Package_Description__c = contents[Math.mod(k, 8)],
            Weight_Kg__c = weight,
            Declared_Value__c = declared,
            Price__c = price,
            Carrier_Cost__c = (price * (0.55 + Math.mod(k, 5) / 20.0)).setScale(2),
            Internal_Notes__c = notes[Math.mod(k, 5)],
            Reschedule_Count__c = 0
        );
        // Dates relative to today so the data is useful whenever it is loaded
        if (status == 'Requested') {
            s.Pickup_Date__c = ShipmentRules.addBusinessDays(today, 1 + Math.mod(k, 5));
            s.Estimated_Delivery__c = ShipmentRules.estimatedDelivery(s.Pickup_Date__c, service);
        } else if (status == 'Delivered') {
            s.Pickup_Date__c = today.addDays(-12 - Math.mod(k, 10));
            s.Estimated_Delivery__c = today.addDays(-4 - Math.mod(k, 5));
            s.Delivered_At__c = Datetime.newInstance(s.Estimated_Delivery__c, Time.newInstance(11 + Math.mod(k, 6), 15, 0, 0));
            s.Last_Update__c = s.Delivered_At__c;
            s.Last_Location__c = dst[0];
            s.Proof_Id__c = 'PRF-' + String.valueOf(88000 + k);
        } else {
            s.Pickup_Date__c = today.addDays(-2 - Math.mod(k, 4));
            s.Estimated_Delivery__c = today.addDays(1 + Math.mod(k, 6));
            s.Last_Update__c = Datetime.now().addHours(-1 - Math.mod(k, 30));
            s.Last_Location__c = status == 'Picked up' ? src[0] : (status == 'Out for delivery' ? dst[0] : (Math.mod(k, 2) == 0 ? 'Centro de distribución ' + src[0] : 'Hub ' + places[Math.mod(k + 2, 8)][0]));
            if (status == 'Exception') {
                s.Last_Location__c = 'Retenido en ' + dst[0] + ': domicilio no localizado';
            }
        }
        s.Original_Estimated_Delivery__c = s.Estimated_Delivery__c;
        shipments.add(s); // insertion order = tracking number order
    }
}
insert shipments;
System.debug('LOADED ' + shipments.size() + ' shipments');
