//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
//

import Foundation

// We generate 100 one-time prekeys at a time.  We should replenish
// whenever ~2/3 of them have been consumed.
let kEphemeralPreKeysMinimumCount: UInt = 35

@objc(SSKRefreshPreKeysOperation)
public class RefreshPreKeysOperation: OWSOperation {

    public override func run() {
        Logger.debug("")

        guard tsAccountManager.isRegistered else {
            Logger.debug("skipping - not registered")
            return
        }

        firstly(on: .global()) { () -> Promise<Void> in
            self.messageProcessor.fetchingAndProcessingCompletePromise()
        }.then(on: .global()) { () -> Promise<Int> in
            self.accountServiceClient.getPreKeysCount()
        }.then(on: .global()) { (preKeysCount: Int) -> Promise<Void> in
            Logger.info("preKeysCount: \(preKeysCount)")
            // PNI TODO: parameterize this entire operation on OWSIdentity
            let signalProtocolStore = self.signalProtocolStore(for: .aci)

            guard preKeysCount < kEphemeralPreKeysMinimumCount ||
                    signalProtocolStore.signedPreKeyStore.currentSignedPrekeyId() == nil else {
                Logger.debug("Available keys sufficient: \(preKeysCount)")
                return Promise.value(())
            }

            let identityKey: Data = self.identityManager.identityKeyPair(for: .aci)!.publicKey
            let signedPreKeyRecord = signalProtocolStore.signedPreKeyStore.generateRandomSignedRecord()
            let preKeyRecords: [PreKeyRecord] = signalProtocolStore.preKeyStore.generatePreKeyRecords()

            self.databaseStorage.write { transaction in
                signalProtocolStore.signedPreKeyStore.storeSignedPreKey(signedPreKeyRecord.id,
                                                                        signedPreKeyRecord: signedPreKeyRecord,
                                                                        transaction: transaction)
                signalProtocolStore.preKeyStore.storePreKeyRecords(preKeyRecords, transaction: transaction)
            }

            return firstly(on: .global()) { () -> Promise<Void> in
                self.accountServiceClient.setPreKeys(for: .aci,
                                                     identityKey: identityKey,
                                                     signedPreKeyRecord: signedPreKeyRecord,
                                                     preKeyRecords: preKeyRecords)
            }.done(on: .global()) { () in
                signedPreKeyRecord.markAsAcceptedByService()

                self.databaseStorage.write { transaction in
                    signalProtocolStore.signedPreKeyStore.storeSignedPreKey(signedPreKeyRecord.id,
                                                                            signedPreKeyRecord: signedPreKeyRecord,
                                                                            transaction: transaction)
                    signalProtocolStore.signedPreKeyStore.setCurrentSignedPrekeyId(signedPreKeyRecord.id,
                                                                                   transaction: transaction)
                    signalProtocolStore.signedPreKeyStore.cullSignedPreKeyRecords(transaction: transaction)
                    signalProtocolStore.signedPreKeyStore.clearPrekeyUpdateFailureCount(transaction: transaction)

                    signalProtocolStore.preKeyStore.cullPreKeyRecords(transaction: transaction)
                }
            }
        }.done(on: .global()) {
            Logger.info("done")
            self.reportSuccess()
        }.catch(on: .global()) { error in
            self.reportError(withUndefinedRetry: error)
        }
    }

    public override func didSucceed() {
        TSPreKeyManager.refreshPreKeysDidSucceed()
    }

    override public func didFail(error: Error) {
        guard !error.isNetworkConnectivityFailure else {
            Logger.debug("don't report PK rotation failure w/ network error")
            return
        }
        guard let statusCode = error.httpStatusCode else {
            Logger.debug("don't report PK rotation failure w/ non NetworkManager error: \(error)")
            return
        }
        guard statusCode >= 400 && statusCode <= 599 else {
            Logger.debug("don't report PK rotation failure w/ non application error")
            return
        }

        let signalProtocolStore = self.signalProtocolStore(for: .aci)
        self.databaseStorage.write { transaction in
            signalProtocolStore.signedPreKeyStore.incrementPrekeyUpdateFailureCount(transaction: transaction)
        }
    }
}
