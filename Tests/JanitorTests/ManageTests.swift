//  ManageTests.swift
//  The Manage window's binding, the Discovery wizard's states, and the settings the two
//  of them share.
//
//  Same discipline as AppModelTests: feed the model what the core would send, and assert
//  what the windows would render. Nothing here reaches into a view.
//
//  The binding rule is the one worth the most care. An Environment that lands in the
//  wrong Application silently retargets a compare column at a different Secret Set, and
//  nothing about the matrix afterwards would look wrong.

import Testing
@testable import Janitor

@MainActor
struct ManageTests {
    private func model() -> AppModel {
        AppModel(core: StubCore())
    }

    private func mapping(_ environment: String, region: String = "us-east-1") -> Mapping {
        Mapping(
            environment: environment,
            accountId: "123456789012",
            region: region,
            secretId: "arn:aws:secretsmanager:\(region):123456789012:secret:\(environment)/app",
            permissionSet: "ReadOnly",
            method: .secretsManager
        )
    }

    // MARK: The binding rule

    @Test("a discovered Environment lands on the Application the window was opened for")
    func discoveryLandsOnTheBoundApplication() {
        let model = model()
        model.openManage(0)

        // The operator moves on while the walk runs.
        model.select(1)
        model.apply(.envDiscovered(mapping: mapping("qa")))

        #expect(model.manage?.application == 0)
        #expect(model.manage?.environments.map(\.environment).contains("qa") == true)

        // Payments API gained it. Auth Service, which is selected, did not.
        #expect(model.apps[0].subtitle == "3 envs")
        #expect(model.apps[1].subtitle == "3 envs")
    }

    @Test("selecting another Application does not retarget the open window")
    func selectionDoesNotRetarget() {
        let model = model()
        model.openManage(2)
        let bound = model.manage?.name

        model.select(0)
        model.select(1)

        #expect(model.manage?.application == 2)
        #expect(model.manage?.name == bound)
    }

    @Test("opening Manage again binds it to the Application that was asked for")
    func explicitOpenRebinds() {
        let model = model()
        model.openManage(0)
        model.openManage(3)

        #expect(model.manage?.application == 3)
        #expect(model.manage?.name == "Notifications")
    }

    @Test("a Mapping arriving with no open window is dropped")
    func discoveryWithNoBoundWindowIsDropped() {
        let model = model()
        model.apply(.envDiscovered(mapping: mapping("qa")))

        #expect(model.manage == nil)
        #expect(model.apps[0].subtitle == "2 envs")
    }

    @Test("an Environment that already exists is refused, not overwritten")
    func duplicateEnvironmentIsRefused() {
        let model = model()
        model.openManage(0)
        let before = model.manage?.environments.count

        model.apply(.envDiscovered(mapping: mapping("prod")))

        #expect(model.manage?.environments.count == before)
        guard case .terminal(let message)? = model.manage?.discovery else {
            Issue.record("a refused duplicate should leave a message to step back from")
            return
        }
        #expect(message.contains("prod"))
    }

    // MARK: The wizard's three states

    @Test("the wizard shows one question at a time")
    func theWizardShowsOneQuestionAtATime() {
        let model = model()
        model.openManage(0)
        model.beginDiscovery(environment: "qa", method: .secretsManager)
        #expect(model.manage?.discovery == .working("Discovering…"))

        model.apply(.discoveryChoice(
            what: .accounts, labels: ["Platform (1)", "Sandbox (2)"], defaultIndex: 1
        ))
        #expect(model.manage?.discovery == .choice(
            prompt: "Choose an account:", labels: ["Platform (1)", "Sandbox (2)"], defaultIndex: 1
        ))

        // The next step replaces the picker rather than appearing beside it.
        model.apply(.discoveryInput(
            what: .filePath, prompt: "Path to the .env file:", defaultText: "/opt/app/.env"
        ))
        #expect(model.manage?.discovery == .input(
            prompt: "Path to the .env file:", text: "/opt/app/.env"
        ))
    }

    @Test("a walk that cannot finish leaves a message to step back from")
    func aFailedWalkIsDismissible() {
        let model = model()
        model.openManage(0)
        model.beginDiscovery(environment: "qa", method: .secretsManager)
        model.apply(.discoveryFailed("no accounts you can access"))

        #expect(model.manage?.discovery == .terminal("Could not add: no accounts you can access"))

        model.dismissDiscovery()
        #expect(model.manage?.discovery == .idle)
    }

    @Test("an expired session routes the main window back to sign-in")
    func reauthRoutesToSignIn() {
        let model = model()
        model.openManage(0)
        model.beginDiscovery(environment: "qa", method: .secretsManager)
        model.apply(.discoveryReauthRequired)

        // Not just a wizard message: the session is gone, so the whole window says so.
        #expect(model.status == .failed)
        #expect(model.banner?.isEmpty == false)
    }

    @Test("an advisory rides beside the question rather than replacing it")
    func anAdvisoryDoesNotReplaceTheQuestion() {
        let model = model()
        model.openManage(0)
        model.beginDiscovery(environment: "qa", method: .ssmDotenv)
        model.apply(.discoveryChoice(what: .instances, labels: ["i-1", "i-2"], defaultIndex: 0))
        model.apply(.warning("session logging archives this read to S3"))

        #expect(model.manage?.advisory == "session logging archives this read to S3")
        guard case .choice? = model.manage?.discovery else {
            Issue.record("the advisory replaced the question")
            return
        }
    }

    @Test("an advisory with no walk in flight goes to the log only")
    func anAdvisoryOutsideAWalkIsLoggedOnly() {
        let model = model()
        model.openManage(0)
        model.apply(.warning("session logging archives this read to S3"))

        #expect(model.manage?.advisory == nil)
        #expect(model.log.contains { $0.message.contains("session logging") })
    }

    // MARK: Editing the Application

    @Test("a blank rename is refused, so a stray Return cannot erase a name")
    func blankRenameIsRefused() {
        let model = model()
        model.openManage(0)
        model.renameManagedApplication(to: "   ")

        #expect(model.manage?.name == "Payments API")
        #expect(model.apps[0].name == "Payments API")
    }

    @Test("a rename reaches the sidebar")
    func renameReachesTheSidebar() {
        let model = model()
        model.openManage(1)
        model.renameManagedApplication(to: "Identity Service")

        #expect(model.manage?.name == "Identity Service")
        #expect(model.apps[1].name == "Identity Service")
    }

    @Test("removing an Environment drops one compare column")
    func removingAnEnvironmentDropsAColumn() {
        let model = model()
        model.openManage(1)
        model.removeManagedEnvironment(at: 0)

        #expect(model.manage?.environments.count == 2)
        #expect(model.apps[1].subtitle == "2 envs")
    }

    @Test("removing the bound Application closes the window")
    func removingTheBoundApplicationClosesTheWindow() {
        let model = model()
        model.openManage(2)
        model.removeApplication(at: 2)

        #expect(model.manage == nil)
        #expect(model.apps.count == 3)
    }

    // MARK: The browse region

    @Test("the browse region is one value, not two pickers")
    func theBrowseRegionIsOneValue() {
        let model = model()
        // Empty means "use the Identity Center region", which is what lets a
        // single-region org never pick one.
        #expect(model.browseRegion == "us-east-1")

        model.setBrowseRegion("eu-west-1")
        #expect(model.browseRegion == "eu-west-1")
    }

    @Test("the picker offers a region the operator already uses")
    func theirOwnRegionsAreOffered() {
        let model = model()

        // Billing Worker is mapped to eu-west-1 and Auth Service to us-west-2.
        #expect(model.regionChoices.contains("eu-west-1"))
        #expect(model.regionChoices.contains("us-west-2"))

        // And a region reached only by a walk shows up once it is saved.
        model.openManage(0)
        model.apply(.envDiscovered(mapping: mapping("gov", region: "us-gov-west-1")))
        #expect(model.regionChoices.contains("us-gov-west-1"))
    }

    // MARK: Write outcomes

    @Test("a refused write says the lock is why, and names no Value")
    func aRefusedWriteIsVisible() {
        let model = model()
        model.apply(.writeRefused(environment: "prod"))

        let lines = model.log.map(\.message)
        #expect(lines.contains { $0.contains("prod") && $0.contains("read-write mode is off") })
    }

    @Test("a conflict says nothing was overwritten")
    func aConflictSaysNothingWasOverwritten() {
        let model = model()
        model.apply(.writeConflict(environment: "staging"))

        #expect(model.log.contains { $0.message.contains("nothing was overwritten") })
    }

    @Test("no write outcome ever carries an edited Value")
    func writeOutcomesCarryNoValue() {
        let model = model()
        model.apply(.writeApplied(environment: "prod"))
        model.apply(.writeFailed(environment: "prod", detail: "the role cannot write this secret"))

        #expect(!model.log.contains { $0.message.contains("hunter2") })
        #expect(model.log.contains { $0.message.contains("edits applied") })
    }
}
