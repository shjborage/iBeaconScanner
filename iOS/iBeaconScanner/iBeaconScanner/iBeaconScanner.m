//
//  iBeaconScanner.m
//  iBeaconScanner
//
//  Created by shihaijie on 9/2/14.
//  Copyright (c) 2014 Saick. All rights reserved.
//

#import "iBeaconScanner.h"
@import CoreBluetooth;

@interface iBeaconScanner()<
CBCentralManagerDelegate,
CBPeripheralDelegate
>

@property (nonatomic, strong) CBCentralManager *manager;
@property (nonatomic, strong) NSMutableDictionary *foundBeacons;
@property (nonatomic, strong) NSMutableArray *peripherals;

@end

@implementation iBeaconScanner

- (id)init
{
  if (self = [super init]) {
    _manager = [[CBCentralManager alloc] initWithDelegate:self queue:nil options:nil];
    _foundBeacons = [NSMutableDictionary dictionary];
    _peripherals = [NSMutableArray array];
  }
  return self;
}

- (void)startScan
{
  /*
   typedef enum {
   CBPeripheralManagerAuthorizationStatusNotDetermined = 0,
   CBPeripheralManagerAuthorizationStatusRestricted,
   CBPeripheralManagerAuthorizationStatusDenied,
   CBPeripheralManagerAuthorizationStatusAuthorized,
   } CBPeripheralManagerAuthorizationStatus;
   */
  NSLog(@"CBPeripheralManager authorizationStatus: [%d]", [CBPeripheralManager authorizationStatus]);
  
  if (self.manager.state == CBCentralManagerStatePoweredOff) {
    // raise an error
    return;
  }
  
  [self.manager scanForPeripheralsWithServices:nil options:nil];
  // Use a timer to control scan interval
}

- (void)stopScan
{
  [self.manager stopScan];
}

#pragma mark - CBCentralManagerDelegate

-(void)centralManagerDidUpdateState:(CBCentralManager *)central
{
  if (self.manager.state == CBCentralManagerStatePoweredOn) {
    [self stopScan];
  }
  
  switch (central.state) {
    case CBCentralManagerStatePoweredOff:
      NSLog(@"Powered Off");
      break;
    case CBCentralManagerStatePoweredOn:
      NSLog(@"Powered On");
      [self startScan];
      break;
    case CBCentralManagerStateResetting:
      NSLog(@"Resetting");
      break;
    case CBCentralManagerStateUnauthorized:
      NSLog(@"Unauthorised");
      break;
    case CBCentralManagerStateUnsupported:
      NSLog(@"Unsupported");
      break;
    case CBCentralManagerStateUnknown:
    default:
      NSLog(@"Unknown");
      break;
  }
}

-(void)centralManager:(CBCentralManager *)central
didDiscoverPeripheral:(CBPeripheral *)peripheral
    advertisementData:(NSDictionary *)advertisementData
                 RSSI:(NSNumber *)RSSI
{
  NSData *advData = [advertisementData objectForKey:@"kCBAdvDataManufacturerData"];
  if ([self advDataIsBeacon:advData]) {
    NSMutableDictionary *beacon = [NSMutableDictionary dictionaryWithDictionary:[self getBeaconInfoFromData:advData]];
    
    //rssi
    [beacon setObject:RSSI forKey:@"RSSI"];
    
    //peripheral uuid
    [beacon setObject:peripheral.identifier.UUIDString forKey:@"deviceUUID"];
    
    //distance
    NSNumber *distance = [self calculatedDistance:[beacon objectForKey:@"power"] RSSI:RSSI];
    if (distance) {
      [beacon setObject:distance forKey:@"distance"];
    }
    
    //proximity
    [beacon setObject:[self proximityFromDistance:distance] forKey:@"proximity"];
    
    //combined uuid
    NSString *uniqueUUID = peripheral.identifier.UUIDString;
    NSString *beaconUUID = beacon[@"uuid"];
    
    if (beaconUUID) {
      uniqueUUID = [uniqueUUID stringByAppendingString:beaconUUID];
    }
    
    // add to beacon dictionary
    [self.foundBeacons setObject:beacon forKey:uniqueUUID];
  } else {
    // connnect to this device
    NSLog(@"%@:%@", peripheral, peripheral.services);
    peripheral.delegate = self;
    [_peripherals addObject:peripheral];
    
    if (peripheral.state == CBPeripheralStateDisconnected) {
      [self.manager connectPeripheral:peripheral options:nil];
    }
  }
}

- (void)centralManager:(CBCentralManager *)central
  didConnectPeripheral:(CBPeripheral *)peripheral
{
  [peripheral discoverServices:nil];
  NSLog(@"%@:%@", peripheral, peripheral.services);
}

- (void)centralManager:(CBCentralManager *)central
didDisconnectPeripheral:(CBPeripheral *)peripheral
                 error:(NSError *)error
{
  
}

- (void)centralManager:(CBCentralManager *)central
didFailToConnectPeripheral:(CBPeripheral *)peripheral
                 error:(NSError *)error
{
  
}

- (void)peripheral:(CBPeripheral *)peripheral
didDiscoverServices:(NSError *)error
{
  NSLog(@"%@", peripheral.services);
  for (CBService *service in peripheral.services) {
    NSLog(@"%@", service);
    NSLog(@"%@", [service includedServices]);
    NSLog(@"%@", [service characteristics]);
  }
}

#pragma mark - iBeacon Core

//algorythm taken from http://stackoverflow.com/a/20434019/814389
//I've seen this method mentioned a couple of times but cannot verify its accuracy
- (NSNumber *)calculatedDistance:(NSNumber *)txPowerNum RSSI:(NSNumber *)RSSINum
{
  int txPower = [txPowerNum intValue];
  double rssi = [RSSINum doubleValue];
  
  if (rssi == 0) {
    return nil; // if we cannot determine accuracy, return nil.
  }
  
  double ratio = rssi * 1.0 / txPower;
  if (ratio < 1.0) {
    return @(pow(ratio, 10.0));
  }
  else {
    double accuracy =  (0.89976) * pow(ratio, 7.7095) + 0.111;
    return @(accuracy);
  }
}

- (BOOL)advDataIsBeacon:(NSData *)data
{
  //TODO: could this be cleaner?
  Byte expectingBytes [4] = { 0x4c, 0x00, 0x02, 0x15 };
  NSData *expectingData = [NSData dataWithBytes:expectingBytes length:sizeof(expectingBytes)];
  
  if (data.length > expectingData.length)
  {
    if ([[data subdataWithRange:NSMakeRange(0, expectingData.length)] isEqual:expectingData])
    {
      return YES;
    }
  }
  
  return NO;
}

- (NSDictionary *)getBeaconInfoFromData:(NSData *)data
{
  NSRange uuidRange = NSMakeRange(4, 16);
  NSRange majorRange = NSMakeRange(20, 2);
  NSRange minorRange = NSMakeRange(22, 2);
  NSRange powerRange = NSMakeRange(24, 1);
  
  Byte uuidBytes[16];
  [data getBytes:&uuidBytes range:uuidRange];
  NSUUID *uuid = [[NSUUID alloc] initWithUUIDBytes:uuidBytes];
  
  uint16_t majorBytes;
  [data getBytes:&majorBytes range:majorRange];
  uint16_t majorBytesBig = (majorBytes >> 8) | (majorBytes << 8);
  
  uint16_t minorBytes;
  [data getBytes:&minorBytes range:minorRange];
  uint16_t minorBytesBig = (minorBytes >> 8) | (minorBytes << 8);
  
  int8_t powerByte;
  [data getBytes:&powerByte range:powerRange];
  
  return @{ @"uuid" : uuid.UUIDString, @"major" : @(majorBytesBig), @"minor" : @(minorBytesBig), @"power" : @(powerByte) };
}

- (NSString *)proximityFromDistance:(NSNumber *)distance
{
  if (distance == nil) {
    distance = @(-1);
  }
  
  if (distance.doubleValue >= 2.0)
    return @"Far";
  if (distance.doubleValue >= 0.25)
    return @"Near";
  if (distance.doubleValue >= 0)
    return @"immediate";
  return @"Unknown";
}

@end
