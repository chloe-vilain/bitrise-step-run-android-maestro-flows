# Run Android Maestro Flows

This step runs your Maestro flows on an Android emulator and exports a test report and a video recording. This step will fail if the maestro tests fail.

## Requirements:
In order to run this step, you will need to have a booted emulator and an app build file to install on it. These can be provided by the AVD Manager & Android Build for UI Testing steps.

We suggest running the steps in the following order, to allow emulator time to boot up fully:

- avd-manager
- android-build-for-ui-testing
- wait-for-android-emulator
- run-android-maestro-flows


Inputs:
- `app_file`: The path to the app build file to install on the emulator. Android Build for UI Testing outputs your app build path to `$BITRISE_APK_PATH`. You can pass this path to the `app_file` input of this step.
- `workspace`: The path to the Maestro flow file or directory that includes Maestro Flows. Default is `.maestro` directory in the root of your project.
- `additional_params`: Additional parameters of Maestro CLI command i.e --include-tags=dev,pull-request
- `maestro_cli_version`: The version of Maestro CLI to be downloaded in your CI. Default is `latest`.

Dependencies:
- `ffmpeg` - This step requires `ffmpeg` to be installed on your machine. The step will try to install it on Mac and Linux machines with brew and apt-get respectively if it is not found.
- `maestro cli` - This step will install the Maestro CLI if it is not found. 


### Tips for running this step locally & debugging

Note that, if you are running this step locally on M-series Mac, your AVD Manager step will need to leverage different processor architecture. You can achieve this by changing the abi to `arm64-v8a` in the AVD Manager step. You may also want to configure your local emulator to run in non-headless mode, for debugging.  Here's an example of setting up your build file to be compatible with M-series Mac for local testing & run the emulator in non-headless mode, while leveeraging the default x86 architecture in bitrise remote environment:

```
- avd-manager@2:
   run_if: "{{not .IsCI}}"
   inputs:
   - abi: arm64-v8a
   - api_level: 30
   - headless_mode: 'no'
- avd-manager@2:
   run_if: ".IsCI"
   inputs:
   - api_level: 30
```

Due to timeout limitations with the adb screen recorder functionality (times out after 3 mintes), this step will run a loop in the background to record the screen in 15-second chunks. The recordings will be merged into a single video file using `ffmpeg` and exported to the deploy directory. If the ffmpeg merge fails (for example, if one of the recordings is corrupted), the individual recordings will be exported instead.

You may wish to add a step to your workflow to kill any local devices when debugging locally, to avoid bugs pertaining to multiple emulators running at once. 

## How to use this Step

Can be run directly with the [bitrise CLI](https://github.com/bitrise-io/bitrise),
just `git clone` this repository, `cd` into it's folder in your Terminal/Command Line
and call `bitrise run test`.

*Check the `bitrise.yml` file for required inputs which have to be
added to your `.bitrise.secrets.yml` file!*

Step by step:

1. Open up your Terminal / Command Line
2. `git clone` the repository
3. `cd` into the directory of the step (the one you just `git clone`d)
5. Create a `.bitrise.secrets.yml` file in the same directory of `bitrise.yml`
   (the `.bitrise.secrets.yml` is a git ignored file, you can store your secrets in it)
6. Check the `bitrise.yml` file for any secret you should set in `.bitrise.secrets.yml`
  * Best practice is to mark these options with something like `# define these in your .bitrise.secrets.yml`, in the `app:envs` section.
7. Once you have all the required secret parameters in your `.bitrise.secrets.yml` you can just run this step with the [bitrise CLI](https://github.com/bitrise-io/bitrise): `bitrise run test`

An example `.bitrise.secrets.yml` file:

```
envs:
- A_SECRET_PARAM_ONE: the value for secret one
- A_SECRET_PARAM_TWO: the value for secret two
```

## How to create your own step

1. Create a new git repository for your step (**don't fork** the *step template*, create a *new* repository)
2. Copy the [step template](https://github.com/bitrise-steplib/step-template) files into your repository
3. Fill the `step.sh` with your functionality
4. Wire out your inputs to `step.yml` (`inputs` section)
5. Fill out the other parts of the `step.yml` too
6. Provide test values for the inputs in the `bitrise.yml`
7. Run your step with `bitrise run test` - if it works, you're ready

__For Step development guidelines & best practices__ check this documentation: [https://github.com/bitrise-io/bitrise/blob/master/_docs/step-development-guideline.md](https://github.com/bitrise-io/bitrise/blob/master/_docs/step-development-guideline.md).

**NOTE:**

If you want to use your step in your project's `bitrise.yml`:

1. git push the step into it's repository
2. reference it in your `bitrise.yml` with the `git::PUBLIC-GIT-CLONE-URL@BRANCH` step reference style:

```
- git::https://github.com/user/my-step.git@branch:
   title: My step
   inputs:
   - my_input_1: "my value 1"
   - my_input_2: "my value 2"
```

You can find more examples of step reference styles
in the [bitrise CLI repository](https://github.com/bitrise-io/bitrise/blob/master/_examples/tutorials/steps-and-workflows/bitrise.yml#L65).

## How to contribute to this Step

1. Fork this repository
2. `git clone` it
3. Create a branch you'll work on
4. To use/test the step just follow the **How to use this Step** section
5. Do the changes you want to
6. Run/test the step before sending your contribution
  * You can also test the step in your `bitrise` project, either on your Mac or on [bitrise.io](https://www.bitrise.io)
  * You just have to replace the step ID in your project's `bitrise.yml` with either a relative path, or with a git URL format
  * (relative) path format: instead of `- original-step-id:` use `- path::./relative/path/of/script/on/your/Mac:`
  * direct git URL format: instead of `- original-step-id:` use `- git::https://github.com/user/step.git@branch:`
  * You can find more example of alternative step referencing at: https://github.com/bitrise-io/bitrise/blob/master/_examples/tutorials/steps-and-workflows/bitrise.yml
7. Once you're done just commit your changes & create a Pull Request


## Share your own Step

You can share your Step or step version with the [bitrise CLI](https://github.com/bitrise-io/bitrise). If you use the `bitrise.yml` included in this repository, all you have to do is:

1. In your Terminal / Command Line `cd` into this directory (where the `bitrise.yml` of the step is located)
1. Run: `bitrise run test` to test the step
1. Run: `bitrise run audit-this-step` to audit the `step.yml`
1. Check the `share-this-step` workflow in the `bitrise.yml`, and fill out the
   `envs` if you haven't done so already (don't forget to bump the version number if this is an update
   of your step!)
1. Then run: `bitrise run share-this-step` to share the step (version) you specified in the `envs`
1. Send the Pull Request, as described in the logs of `bitrise run share-this-step`

That's all ;)
