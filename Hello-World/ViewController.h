//
//  ViewController.h
//  Hello-World
//
//  Copyright (c) 2013 TokBox, Inc. All rights reserved.
//

#import <UIKit/UIKit.h>

@interface ViewController : UIViewController
{
    
}
@property (strong, nonatomic) IBOutlet UITextField *pubDimensionsTxtFld;
@property (strong, nonatomic) IBOutlet UITextField *subDimensionsTxtFld;
@property (strong, nonatomic) IBOutlet UITextField *cpuUsageTxtFld;
@property (strong, nonatomic) IBOutlet UITextField *memUsageTxtFld;
@property (strong, nonatomic) IBOutlet UISwitch *vp8SwitchOn;
@property (strong, nonatomic) IBOutlet UILabel *batteryLevel;

- (IBAction)sampleCPUUsage:(id)sender;

@end
