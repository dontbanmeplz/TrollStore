#import "TSAppTableViewController.h"
#import "TSSceneDelegate.h"
#import "TSApplicationsManager.h"

#define ICON_FORMAT_IPAD 8
#define ICON_FORMAT_IPHONE 10

NSInteger iconFormatToUse(void)
{
	if(UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPad)
	{
		return ICON_FORMAT_IPAD;
	}
	else
	{
		return ICON_FORMAT_IPHONE;
	}
}

UIImage* imageWithSize(UIImage* image, CGSize size)
{
	if(CGSizeEqualToSize(image.size, size)) return image;
	UIGraphicsBeginImageContextWithOptions(size, NO, UIScreen.mainScreen.scale);
	CGRect imageRect = CGRectMake(0.0, 0.0, size.width, size.height);
	[image drawInRect:imageRect];
	UIImage* outImage = UIGraphicsGetImageFromCurrentImageContext();
	UIGraphicsEndImageContext();
	return outImage;
}

@interface UIImage ()
+ (UIImage *)_applicationIconImageForBundleIdentifier:(NSString *)id format:(NSInteger)format scale:(double)scale;
@end

@implementation TSAppTableViewController

- (void)loadCachedAppPaths
{
	NSArray* appPaths = [[TSApplicationsManager sharedInstance] installedAppPaths];

	_cachedAppPaths = [appPaths sortedArrayUsingComparator:^NSComparisonResult(NSString* appPathA, NSString* appPathB) {
		NSString* displayNameA = [[TSApplicationsManager sharedInstance] displayNameForAppPath:appPathA];
		NSString* displayNameB = [[TSApplicationsManager sharedInstance] displayNameForAppPath:appPathB];

		return [displayNameA localizedStandardCompare:displayNameB];
	}];
}

- (instancetype)init
{
	self = [super init];
	if(self)
	{
		[self loadCachedAppPaths];
		_placeholderIcon = [UIImage _applicationIconImageForBundleIdentifier:@"com.apple.WebSheet" format:iconFormatToUse() scale:[UIScreen mainScreen].scale];
		_cachedIcons = [NSMutableDictionary new];
	}
	return self;
}

- (void)reloadTable
{
	[self loadCachedAppPaths];
	dispatch_async(dispatch_get_main_queue(), ^
	{
		[self.tableView reloadData];
	});
}

- (void)loadView
{
	[super loadView];
	[[NSNotificationCenter defaultCenter] addObserver:self
			selector:@selector(reloadTable)
			name:@"ApplicationsChanged"
			object:nil];
}

- (void)installFromRepo {
	// check for saved repos
	NSArray *savedRepos = [[NSUserDefaults standardUserDefaults] objectForKey:@"savedRepos"];
	if (savedRepos.count == 0) {
			UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Install from repo" message:@"Enter the repo URL" preferredStyle:UIAlertControllerStyleAlert];
			[alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
				textField.placeholder = @"Repo URL";
			}];
			UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil];
			UIAlertAction *installAction = [UIAlertAction actionWithTitle:@"Add Repo" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) 
			{
				// add repo
				NSMutableArray *newRepos = [NSMutableArray arrayWithArray:savedRepos];
				[newRepos addObject:alert.textFields.firstObject.text];
				[[NSUserDefaults standardUserDefaults] setObject:newRepos forKey:@"savedRepos"];
				[[NSUserDefaults standardUserDefaults] synchronize];
				dispatch_async(dispatch_get_main_queue(), ^{
					[self installFromRepo];
				});
			}];
			[alert addAction:cancelAction];
			[alert addAction:installAction];
			[self presentViewController:alert animated:YES completion:nil];
	} else {
		UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Install from repo" message:@"Select a repo" preferredStyle:UIAlertControllerStyleAlert];
		for (NSString *repo in savedRepos) {
			UIAlertAction *action = [UIAlertAction actionWithTitle:repo style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
				// install
				NSString *repoURL = repo;
				// download the repo
				NSURL *url = [NSURL URLWithString:repoURL];
				NSURLSessionDataTask *downloadTask = [[NSURLSession sharedSession] dataTaskWithURL:url completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
					if (error) {
						// error
						dispatch_async(dispatch_get_main_queue(), ^{
							UIAlertController *errorAlert = [UIAlertController alertControllerWithTitle:@"Error" message:error.localizedDescription preferredStyle:UIAlertControllerStyleAlert];
							[errorAlert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
							[self presentViewController:errorAlert animated:YES completion:nil];
						});
					} else {
						// parse the repo ( get all apps and ask the user which one to install )
						NSError *jsonError;
						NSDictionary *repo = [NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingMutableContainers error:&jsonError];
						if (jsonError) {
							// error
							dispatch_async(dispatch_get_main_queue(), ^{
								UIAlertController *errorAlert = [UIAlertController alertControllerWithTitle:@"Error" message:jsonError.localizedDescription preferredStyle:UIAlertControllerStyleAlert];
								[errorAlert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
								[self presentViewController:errorAlert animated:YES completion:nil];
							});
						} else {
							// parse the repo
							NSArray *apps = repo[@"apps"];
							dispatch_async(dispatch_get_main_queue(), ^{
								UIAlertController *appAlert = [UIAlertController alertControllerWithTitle:@"Select an app" message:nil preferredStyle:UIAlertControllerStyleActionSheet];
									for (NSDictionary *app in apps) {
									[appAlert addAction:[UIAlertAction actionWithTitle:app[@"name"] style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
										// download the ipa, then install it
										NSURL *url = [NSURL URLWithString:app[@"downloadURL"]];
										UIAlertController *progressAlert = [UIAlertController alertControllerWithTitle:@"Downloading..." message:nil preferredStyle:UIAlertControllerStyleAlert];
										[progressAlert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
										[self presentViewController:progressAlert animated:YES completion:nil];
										NSURLSessionDataTask *downloadTask = [[NSURLSession sharedSession] dataTaskWithURL:url completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
											if (error) {
												// error
												UIAlertController *errorAlert = [UIAlertController alertControllerWithTitle:@"Error" message:error.localizedDescription preferredStyle:UIAlertControllerStyleAlert];
												[errorAlert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
												[self presentViewController:errorAlert animated:YES completion:nil];
											} else {
												// download the ipa
												// save the ipa to the documents directory
												NSString *documentsDirectory = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
												NSString *filePath = [documentsDirectory stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.ipa", app[@"bundleIdentifier"]]];
												[data writeToFile:filePath atomically:YES];
												// install ipa ON THE MAIN THREAD
												dispatch_async(dispatch_get_main_queue(), ^{
													// first dismiss the progress alert controller
													[self dismissViewControllerAnimated:YES completion:nil];
													// get the scene delegate and call the install method
												    TSSceneDelegate *sceneDelegate = (TSSceneDelegate *)self.view.window.windowScene.delegate;
													[sceneDelegate doIPAInstall:filePath scene:(UIWindowScene *)self.view.window.windowScene force:NO completion:^{
														// done
														UIAlertController *doneAlert = [UIAlertController alertControllerWithTitle:@"Done" message:@"The app has been installed" preferredStyle:UIAlertControllerStyleAlert];
														[doneAlert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
														[self presentViewController:doneAlert animated:YES completion:nil];
														// remove the ipa
														[[NSFileManager defaultManager] removeItemAtPath:filePath error:nil];
													}];
												});
												
											}
										}];
										[downloadTask resume];
									}]];
								}
								[appAlert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
								[self presentViewController:appAlert animated:YES completion:nil];
							});
						}
					}
				}];
				[downloadTask resume];
			}];
			[alert addAction:action];
		}
		[alert addAction:[UIAlertAction actionWithTitle:@"Add repo" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
			// add repo
			UIAlertController *addRepoAlert = [UIAlertController alertControllerWithTitle:@"Add repo" message:nil preferredStyle:UIAlertControllerStyleAlert];
			[addRepoAlert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
				textField.placeholder = @"Repo URL";
			}];
			[addRepoAlert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
			[addRepoAlert addAction:[UIAlertAction actionWithTitle:@"Add" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
				// add the repo to saved repos
				// but first check for duplicates
				NSArray *savedRepos = [[NSUserDefaults standardUserDefaults] objectForKey:@"savedRepos"];
				for (NSString *savedRepo in savedRepos) {
					if ([savedRepo isEqualToString:addRepoAlert.textFields.firstObject.text]) {
						// duplicate
						UIAlertController *duplicateAlert = [UIAlertController alertControllerWithTitle:@"Error" message:@"This repo is already saved" preferredStyle:UIAlertControllerStyleAlert];
						[duplicateAlert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
						[self presentViewController:duplicateAlert animated:YES completion:nil];
						return;
					}
				}
				NSMutableArray *newRepos = [NSMutableArray arrayWithArray:savedRepos];
				[newRepos addObject:addRepoAlert.textFields.firstObject.text];
				[[NSUserDefaults standardUserDefaults] setObject:newRepos forKey:@"savedRepos"];
				[[NSUserDefaults standardUserDefaults] synchronize];
				dispatch_async(dispatch_get_main_queue(), ^{
					[self installFromRepo];
				});
			}]];
			[self presentViewController:addRepoAlert animated:YES completion:nil];
		}]];
		// remove repo
		[alert addAction:[UIAlertAction actionWithTitle:@"Remove repo" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
			// let user select a repo to remove
			UIAlertController *removeRepoAlert = [UIAlertController alertControllerWithTitle:@"Remove repo" message:nil preferredStyle:UIAlertControllerStyleAlert];
			for (NSString *repo in savedRepos) {
				[removeRepoAlert addAction:[UIAlertAction actionWithTitle:repo style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
					// remove the repo from saved repos
					NSMutableArray *newRepos = [NSMutableArray arrayWithArray:savedRepos];
					[newRepos removeObject:repo];
					[[NSUserDefaults standardUserDefaults] setObject:newRepos forKey:@"savedRepos"];
					[[NSUserDefaults standardUserDefaults] synchronize];
					dispatch_async(dispatch_get_main_queue(), ^{
						[self installFromRepo];
					});
				}]];
			}
			[removeRepoAlert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
			[self presentViewController:removeRepoAlert animated:YES completion:nil];
		}]];
		[alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
		[self presentViewController:alert animated:YES completion:nil];
	}
}

- (void)viewDidLoad {
	[super viewDidLoad];
	
	self.tableView.allowsMultipleSelectionDuringEditing = NO;
	// add a option to install from repo
	self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAdd target:self action:@selector(installFromRepo)];
}

- (void)showError:(NSError*)error
{
	UIAlertController* errorAlert = [UIAlertController alertControllerWithTitle:[NSString stringWithFormat:@"Error %ld", error.code] message:error.localizedDescription preferredStyle:UIAlertControllerStyleAlert];
	UIAlertAction* closeAction = [UIAlertAction actionWithTitle:@"Close" style:UIAlertActionStyleDefault handler:nil];
	[errorAlert addAction:closeAction];
	[self presentViewController:errorAlert animated:YES completion:nil];
}

- (void)openAppPressedForRowAtIndexPath:(NSIndexPath *)indexPath
{
	TSApplicationsManager* appsManager = [TSApplicationsManager sharedInstance];

	NSString* appPath = _cachedAppPaths[indexPath.row];
	NSString* appId = [appsManager appIdForAppPath:appPath];
	BOOL didOpen = [appsManager openApplicationWithBundleID:appId];

	// if we failed to open the app, show an alert
	if (!didOpen) {
		NSString *failMessage = [NSString stringWithFormat: @"Failed to open %@", appId];
		UIAlertController* didFailController = [UIAlertController alertControllerWithTitle:failMessage message: nil preferredStyle:UIAlertControllerStyleAlert];
		UIAlertAction* cancelAction = [UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil];

		[didFailController addAction: cancelAction];
		[self presentViewController:didFailController animated:YES completion:nil];
	}
}

- (void)uninstallPressedForRowAtIndexPath:(NSIndexPath*)indexPath
{
	TSApplicationsManager* appsManager = [TSApplicationsManager sharedInstance];

	NSString* appPath = _cachedAppPaths[indexPath.row];
	NSString* appId = [appsManager appIdForAppPath:appPath];
	NSString* appName = [appsManager displayNameForAppPath:appPath];

	UIAlertController* confirmAlert = [UIAlertController alertControllerWithTitle:@"Confirm Uninstallation" message:[NSString stringWithFormat:@"Uninstalling the app '%@' will delete the app and all data associated to it.", appName] preferredStyle:UIAlertControllerStyleAlert];

	UIAlertAction* uninstallAction = [UIAlertAction actionWithTitle:@"Uninstall" style:UIAlertActionStyleDestructive handler:^(UIAlertAction* action)
	{
		if(appId)
		{
			[appsManager uninstallApp:appId];
		}
		else
		{
			[appsManager uninstallAppByPath:appPath];
		}
	}];
	[confirmAlert addAction:uninstallAction];

	UIAlertAction* cancelAction = [UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil];
	[confirmAlert addAction:cancelAction];

	[self presentViewController:confirmAlert animated:YES completion:nil];
}

- (void)deselectRow
{
	[self.tableView deselectRowAtIndexPath:[self.tableView indexPathForSelectedRow] animated:YES];
}

#pragma mark - Table view data source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
	return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	return _cachedAppPaths.count;
}

- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection
{
	[self reloadTable];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"ApplicationCell"];
	if (!cell) {
		cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"ApplicationCell"];
	}

	NSString* appPath = _cachedAppPaths[indexPath.row];
	NSString* appId = [[TSApplicationsManager sharedInstance] appIdForAppPath:appPath];
	NSString* appVersion = [[TSApplicationsManager sharedInstance] versionStringForAppPath:appPath];

	// Configure the cell...
	cell.textLabel.text = [[TSApplicationsManager sharedInstance] displayNameForAppPath:appPath];
	cell.detailTextLabel.text = [NSString stringWithFormat:@"%@ • %@", appVersion, appId];
	cell.imageView.layer.borderWidth = 1;
	cell.imageView.layer.borderColor = [UIColor.labelColor colorWithAlphaComponent:0.1].CGColor;
	cell.imageView.layer.cornerRadius = 13.5;
	cell.imageView.layer.masksToBounds = YES;
	cell.imageView.layer.cornerCurve = kCACornerCurveContinuous;

	if(appId)
	{
		UIImage* cachedIcon = _cachedIcons[appId];
		if(cachedIcon)
		{
			cell.imageView.image = cachedIcon;
		}
		else
		{
			cell.imageView.image = _placeholderIcon;
			dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^
			{
				//usleep(1000 * 5000); // (test delay for debugging)
				UIImage* iconImage = imageWithSize([UIImage _applicationIconImageForBundleIdentifier:appId format:iconFormatToUse() scale:[UIScreen mainScreen].scale], _placeholderIcon.size);
				_cachedIcons[appId] = iconImage;
				dispatch_async(dispatch_get_main_queue(), ^{
					if([tableView.indexPathsForVisibleRows containsObject:indexPath])
					{
						cell.imageView.image = iconImage;
						[cell setNeedsLayout];
					}
				});
			});
		}
	}
	else
	{
		cell.imageView.image = _placeholderIcon;
	}

	cell.preservesSuperviewLayoutMargins = NO;
	cell.separatorInset = UIEdgeInsetsZero;
	cell.layoutMargins = UIEdgeInsetsZero;

	return cell;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
	return 80.0f;
}

- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath
{
	if(editingStyle == UITableViewCellEditingStyleDelete)
	{
		[self uninstallPressedForRowAtIndexPath:indexPath];
	}
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
	TSApplicationsManager* appsManager = [TSApplicationsManager sharedInstance];

	NSString* appPath = _cachedAppPaths[indexPath.row];
	NSString* appId = [appsManager appIdForAppPath:appPath];
	NSString* appName = [appsManager displayNameForAppPath:appPath];

	UIAlertController* appSelectAlert = [UIAlertController alertControllerWithTitle:appName message:appId?:@"" preferredStyle:UIAlertControllerStyleActionSheet];

	/*UIAlertAction* detachAction = [UIAlertAction actionWithTitle:@"Detach from TrollStore" style:UIAlertActionStyleDefault handler:^(UIAlertAction* action)
	{
		int detachRet = [appsManager detachFromApp:appId];
		if(detachRet != 0)
		{
			[self showError:[appsManager errorForCode:detachRet]];
		}
		[self deselectRow];
	}];
	[appSelectAlert addAction:detachAction];*/


	UIAlertAction* openAction = [UIAlertAction actionWithTitle:@"Open" style:UIAlertActionStyleDefault handler:^(UIAlertAction* action)
	{
		[self openAppPressedForRowAtIndexPath:indexPath];
		[self deselectRow];
	}];
	[appSelectAlert addAction: openAction];

	UIAlertAction* uninstallAction = [UIAlertAction actionWithTitle:@"Uninstall App" style:UIAlertActionStyleDestructive handler:^(UIAlertAction* action)
	{
		[self uninstallPressedForRowAtIndexPath:indexPath];
		[self deselectRow];
	}];
	[appSelectAlert addAction:uninstallAction];

	UIAlertAction* cancelAction = [UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:^(UIAlertAction* action)
	{
		[self deselectRow];
	}];
	[appSelectAlert addAction:cancelAction];

	appSelectAlert.popoverPresentationController.sourceView = tableView;
	appSelectAlert.popoverPresentationController.sourceRect = [tableView rectForRowAtIndexPath:indexPath];

	[self presentViewController:appSelectAlert animated:YES completion:nil];
}

@end