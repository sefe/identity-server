Adding a Post-Deployment Script
=
To include a post-deployment script, place your script in the appropriate subfolder under the Post directory. The folder you choose determines the execution order. There are three available options:

- **BeforeEnvironmentSpecific**
Scripts in this folder are executed first.
Path: Post/BeforeEnvironmentSpecific

- **EnvironmentSpecific**
Executed after all scripts in BeforeEnvironmentSpecific.
Path: Post/EnvironmentSpecific/{environmentTier}
(Replace {environmentTier} with your environment, e.g., DV, QA, PP, etc.)

- **AfterEnvironmentSpecific**
Executed after all scripts in both BeforeEnvironmentSpecific and EnvironmentSpecific.
Path: Post/AfterEnvironmentSpecific

?? Important: Run the Custom Tool
=
After adding your script file, you must run the Custom Tool to ensure it’s included in the final deployment.

Steps:

1. Right-click on the PostDeploymentAggregation.tt file.

2. Select Run Custom Tool.

This will regenerate the PostDeploymentAggregation.sqlscript file to include your new script.

?? Note:
=
If you skip this step, your script will not be included in the DACPAC, and will not be deployed.