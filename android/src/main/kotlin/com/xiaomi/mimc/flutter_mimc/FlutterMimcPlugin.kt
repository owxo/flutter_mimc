package com.xiaomi.mimc.flutter_mimc

import android.content.Context
import android.os.Handler
import android.os.Looper
import com.xiaomi.mimc.MIMCGroupMessage
import com.xiaomi.mimc.MIMCMessage
import com.xiaomi.mimc.MIMCMessageHandler
import com.xiaomi.mimc.MIMCOnlineMessageAck
import com.xiaomi.mimc.MIMCOnlineStatusListener
import com.xiaomi.mimc.MIMCRtsCallHandler
import com.xiaomi.mimc.MIMCRtsChannelHandler
import com.xiaomi.mimc.MIMCServerAck
import com.xiaomi.mimc.MIMCTokenFetcher
import com.xiaomi.mimc.MIMCUnlimitedGroupHandler
import com.xiaomi.mimc.MIMCUser
import com.xiaomi.mimc.common.MIMCConstant
import com.xiaomi.mimc.data.ChannelUser
import com.xiaomi.mimc.data.DataPriority
import com.xiaomi.mimc.data.LaunchedResponse
import com.xiaomi.mimc.data.MIMCStreamConfig
import com.xiaomi.mimc.data.RtsChannelType
import com.xiaomi.mimc.data.RtsDataType
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.atomic.AtomicLong

class FlutterMimcPlugin :
    FlutterPlugin,
    MethodChannel.MethodCallHandler,
    EventChannel.StreamHandler {

    private lateinit var applicationContext: Context
    private lateinit var methodChannel: MethodChannel
    private lateinit var eventChannel: EventChannel
    private val mainHandler = Handler(Looper.getMainLooper())
    private val requestIds = AtomicLong(1)
    private val pendingCreates = ConcurrentHashMap<Long, MethodChannel.Result>()
    private val pendingJoins = ConcurrentHashMap<Long, MethodChannel.Result>()
    private val pendingQuits = ConcurrentHashMap<Long, MethodChannel.Result>()
    private val pendingDismisses = ConcurrentHashMap<Long, MethodChannel.Result>()

    @Volatile private var eventSink: EventChannel.EventSink? = null
    @Volatile private var user: MIMCUser? = null
    @Volatile private var token: String = ""
    @Volatile private var acceptIncomingRtsCalls = false
    @Volatile private var incomingRtsDescription = "Rejected by application policy"

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        applicationContext = binding.applicationContext
        methodChannel = MethodChannel(binding.binaryMessenger, METHODS_CHANNEL)
        eventChannel = EventChannel(binding.binaryMessenger, EVENTS_CHANNEL)
        methodChannel.setMethodCallHandler(this)
        eventChannel.setStreamHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "getCapabilities" -> result.success(CAPABILITIES)
                "initialize" -> initialize(call, result)
                "updateToken" -> {
                    val updatedToken = call.argument<String>("token").orEmpty()
                    if (updatedToken.isBlank()) {
                        result.error("invalid_token", "Token is empty", null)
                    } else {
                        token = updatedToken
                        result.success(null)
                    }
                }
                "login" -> completeBooleanRequest(result, "login", requireUser().login())
                "logout" -> completeBooleanRequest(result, "logout", requireUser().logout())
                "isOnline" -> result.success(requireUser().isOnline)
                "sendMessage" -> result.success(
                    requireUser().sendMessage(
                        requireArgument(call, "toAccount"),
                        requirePayload(call),
                        call.argument<String>("bizType").orEmpty(),
                        call.argument<Boolean>("store") ?: true,
                    ),
                )
                "sendGroupMessage" -> result.success(
                    requireUser().sendGroupMessage(
                        requireLong(call, "topicId"),
                        requirePayload(call),
                        call.argument<String>("bizType").orEmpty(),
                        call.argument<Boolean>("store") ?: true,
                    ),
                )
                "sendOnlineMessage" -> result.success(
                    requireUser().sendOnlineMessage(
                        requireArgument(call, "toAccount"),
                        requirePayload(call),
                        call.argument<String>("bizType").orEmpty(),
                    ),
                )
                "sendUnlimitedGroupMessage" -> result.success(
                    requireUser().sendUnlimitedGroupMessage(
                        requireLong(call, "topicId"),
                        requirePayload(call),
                        call.argument<String>("bizType").orEmpty(),
                        call.argument<Boolean>("store") ?: true,
                    ),
                )
                "createUnlimitedGroup" -> createUnlimitedGroup(call, result)
                "joinUnlimitedGroup" -> joinUnlimitedGroup(call, result)
                "quitUnlimitedGroup" -> quitUnlimitedGroup(call, result)
                "dismissUnlimitedGroup" -> dismissUnlimitedGroup(call, result)
                "setRtsIncomingCallPolicy" -> setRtsIncomingCallPolicy(call, result)
                "configureRtsStream" -> configureRtsStream(call, result)
                "configureRtsBuffers" -> configureRtsBuffers(call, result)
                "getRtsBufferState" -> getRtsBufferState(result)
                "clearRtsBuffers" -> {
                    requireUser().clearSendBuffer()
                    requireUser().clearRecvBuffer()
                    result.success(null)
                }
                "dialRtsCall" -> dialRtsCall(call, result)
                "closeRtsCall" -> closeRtsCall(call, result)
                "sendRtsData" -> sendRtsData(call, result)
                "createRtsChannel" -> createRtsChannel(call, result)
                "joinRtsChannel" -> joinRtsChannel(call, result)
                "leaveRtsChannel" -> leaveRtsChannel(call, result)
                "getRtsChannelMembers" -> getRtsChannelMembers(call, result)
                "dispose" -> {
                    disposeUser()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        } catch (error: Throwable) {
            result.error("android_error", error.message ?: error.javaClass.name, null)
        }
    }

    private fun initialize(call: MethodCall, result: MethodChannel.Result) {
        val appId = requireLong(call, "appId")
        val appAccount = requireArgument(call, "appAccount")
        val resource = call.argument<String>("resource").orEmpty()
        val initialToken = requireArgument(call, "token")

        disposeUser()

        acceptIncomingRtsCalls =
            call.argument<String>("rtsIncomingCallPolicy") == "accept"
        incomingRtsDescription =
            call.argument<String>("rtsIncomingCallDescription").orEmpty()

        val configuredCache = call.argument<String>("cacheDirectory")
        val cachePath = configuredCache?.takeIf(String::isNotBlank)
            ?: applicationContext.externalCacheDir?.absolutePath
            ?: applicationContext.cacheDir.absolutePath
        val dataPath = File(applicationContext.filesDir, "mimc").apply { mkdirs() }.absolutePath

        val created = if (resource.isBlank()) {
            MIMCUser.newInstance(appId, appAccount, cachePath, dataPath)
        } else {
            MIMCUser.newInstance(appId, appAccount, resource, cachePath, dataPath)
        } ?: throw IllegalStateException("MIMCUser.newInstance returned null")

        token = initialToken
        created.registerTokenFetcher(TokenFetcher())
        created.registerOnlineStatusListener(StatusListener())
        created.registerMessageHandler(MessageListener())
        created.registerUnlimitedGroupHandler(UnlimitedGroupListener())
        created.registerRtsCallHandler(RtsCallListener())
        created.registerChannelHandler(RtsChannelListener())
        user = created
        result.success(null)
    }

    private fun createUnlimitedGroup(call: MethodCall, result: MethodChannel.Result) {
        val currentUser = requireUser()
        val topicName = requireArgument(call, "topicName")
        val requestId = requestIds.getAndIncrement()
        pendingCreates[requestId] = result
        try {
            currentUser.createUnlimitedGroup(topicName, requestId)
        } catch (error: Throwable) {
            pendingCreates.remove(requestId)
            throw error
        }
    }

    private fun joinUnlimitedGroup(call: MethodCall, result: MethodChannel.Result) {
        val currentUser = requireUser()
        val topicId = requireLong(call, "topicId")
        val requestId = requestIds.getAndIncrement()
        pendingJoins[requestId] = result
        val packetId = try {
            currentUser.joinUnlimitedGroup(topicId, requestId)
        } catch (error: Throwable) {
            pendingJoins.remove(requestId)
            throw error
        }
        if (packetId.isNullOrEmpty()) {
            pendingJoins.remove(requestId)?.error(
                "uc_join_not_queued",
                "Join request was not queued",
                null,
            )
        }
    }

    private fun quitUnlimitedGroup(call: MethodCall, result: MethodChannel.Result) {
        val currentUser = requireUser()
        val topicId = requireLong(call, "topicId")
        val requestId = requestIds.getAndIncrement()
        pendingQuits[requestId] = result
        val packetId = try {
            currentUser.quitUnlimitedGroup(topicId, requestId)
        } catch (error: Throwable) {
            pendingQuits.remove(requestId)
            throw error
        }
        if (packetId.isNullOrEmpty()) {
            pendingQuits.remove(requestId)?.error(
                "uc_quit_not_queued",
                "Quit request was not queued",
                null,
            )
        }
    }

    private fun dismissUnlimitedGroup(call: MethodCall, result: MethodChannel.Result) {
        val currentUser = requireUser()
        val topicId = requireLong(call, "topicId")
        val requestId = requestIds.getAndIncrement()
        pendingDismisses[requestId] = result
        try {
            currentUser.dismissUnlimitedGroup(topicId, requestId)
        } catch (error: Throwable) {
            pendingDismisses.remove(requestId)
            throw error
        }
    }

    private fun setRtsIncomingCallPolicy(call: MethodCall, result: MethodChannel.Result) {
        requireUser()
        acceptIncomingRtsCalls = requireArgument(call, "policy") == "accept"
        incomingRtsDescription = call.argument<String>("description").orEmpty()
        result.success(null)
    }

    private fun configureRtsStream(call: MethodCall, result: MethodChannel.Result) {
        val strategy = when (requireArgument(call, "strategy")) {
            "fec" -> MIMCStreamConfig.STRATEGY_FEC
            "ack" -> MIMCStreamConfig.STRATEGY_ACK
            else -> throw IllegalArgumentException("Unknown RTS stream strategy")
        }
        val ackWaitTimeMs = requireInt(call, "ackWaitTimeMs", minimum = 0)
        val encrypt = call.argument<Boolean>("encrypt") ?: true
        val config = MIMCStreamConfig(strategy, ackWaitTimeMs, encrypt)
        when (requireArgument(call, "dataType")) {
            "audio" -> requireUser().initAudioStreamConfig(config)
            "video" -> requireUser().initVideoStreamConfig(config)
            else -> throw IllegalArgumentException("Unknown RTS data type")
        }
        result.success(null)
    }

    private fun configureRtsBuffers(call: MethodCall, result: MethodChannel.Result) {
        val sendSize = requireInt(call, "sendSize", minimum = 1)
        val receiveSize = requireInt(call, "receiveSize", minimum = 1)
        requireUser().apply {
            setSendBufferSize(sendSize)
            setRecvBufferSize(receiveSize)
        }
        result.success(null)
    }

    private fun getRtsBufferState(result: MethodChannel.Result) {
        val currentUser = requireUser()
        result.success(
            mapOf(
                "sendSize" to currentUser.sendBufferSize,
                "receiveSize" to currentUser.recvBufferSize,
                "sendUsageRate" to currentUser.sendBufferUsageRate.toDouble(),
                "receiveUsageRate" to currentUser.recvBufferUsageRate.toDouble(),
            ),
        )
    }

    private fun dialRtsCall(call: MethodCall, result: MethodChannel.Result) {
        val callId = requireUser().dialCall(
            requireArgument(call, "toAccount"),
            call.argument<String>("toResource").orEmpty(),
            call.argument<ByteArray>("appContent") ?: ByteArray(0),
        )
        if (callId < 0) result.error("rts_dial_failed", "RTS call was not queued", null)
        else result.success(callId)
    }

    private fun closeRtsCall(call: MethodCall, result: MethodChannel.Result) {
        requireUser().closeCall(
            requirePositiveLong(call, "callId"),
            call.argument<String>("reason").orEmpty(),
        )
        result.success(null)
    }

    private fun sendRtsData(call: MethodCall, result: MethodChannel.Result) {
        val dataType = when (requireArgument(call, "dataType")) {
            "audio" -> RtsDataType.AUDIO
            "video" -> RtsDataType.VIDEO
            else -> throw IllegalArgumentException("Unknown RTS data type")
        }
        val priority = when (requireArgument(call, "priority")) {
            "p0" -> DataPriority.P0
            "p1" -> DataPriority.P1
            "p2" -> DataPriority.P2
            else -> throw IllegalArgumentException("Unknown RTS priority")
        }
        val channelType = when (requireArgument(call, "channelType")) {
            "automatic" -> null
            "relay" -> RtsChannelType.RELAY
            "p2pInternet" -> RtsChannelType.P2P_INTERNET
            "p2pIntranet" -> RtsChannelType.P2P_INTRANET
            else -> throw IllegalArgumentException("Unknown RTS channel type")
        }
        val dataId = requireUser().sendRtsData(
            requirePositiveLong(call, "callId"),
            requirePayload(call),
            dataType,
            priority,
            call.argument<Boolean>("canBeDropped") ?: false,
            requireInt(call, "resendCount", minimum = 0),
            channelType,
            call.argument<String>("context").orEmpty(),
        )
        if (dataId < 0) result.error("rts_send_failed", "RTS data was not queued", null)
        else result.success(dataId)
    }

    private fun createRtsChannel(call: MethodCall, result: MethodChannel.Result) {
        val identity = requireUser().createChannel(
            call.argument<ByteArray>("extra") ?: ByteArray(0),
        )
        if (identity < 0) result.error("rts_channel_create_failed", "Channel was not queued", null)
        else result.success(identity)
    }

    private fun joinRtsChannel(call: MethodCall, result: MethodChannel.Result) {
        requireUser().joinChannel(
            requirePositiveLong(call, "callId"),
            requireArgument(call, "callKey"),
        )
        result.success(null)
    }

    private fun leaveRtsChannel(call: MethodCall, result: MethodChannel.Result) {
        requireUser().leaveChannel(
            requirePositiveLong(call, "callId"),
            requireArgument(call, "callKey"),
        )
        result.success(null)
    }

    private fun getRtsChannelMembers(call: MethodCall, result: MethodChannel.Result) {
        result.success(
            requireUser().getChannelUsers(requirePositiveLong(call, "callId"))
                .map(::channelMemberMap),
        )
    }

    private fun requireUser(): MIMCUser =
        user ?: throw IllegalStateException("MIMC is not initialized")

    private fun completeBooleanRequest(
        result: MethodChannel.Result,
        operation: String,
        accepted: Boolean,
    ) {
        if (accepted) result.success(null)
        else result.error("${operation}_not_queued", "MIMC rejected $operation", null)
    }

    private fun requirePayload(call: MethodCall): ByteArray =
        call.argument<ByteArray>("payload")
            ?: throw IllegalArgumentException("payload is required")

    private fun requireLong(call: MethodCall, key: String): Long {
        val raw = call.argument<Any>(key)
        return when (raw) {
            is Number -> raw.toLong()
            is String -> raw.toLongOrNull()
            else -> null
        } ?: throw IllegalArgumentException("$key must be an integer")
    }

    private fun requirePositiveLong(call: MethodCall, key: String): Long =
        requireLong(call, key).takeIf { it > 0 }
            ?: throw IllegalArgumentException("$key must be greater than zero")

    private fun requireInt(call: MethodCall, key: String, minimum: Int): Int {
        val value = call.argument<Number>(key)?.toInt()
            ?: throw IllegalArgumentException("$key is required")
        if (value < minimum) throw IllegalArgumentException("$key must be >= $minimum")
        return value
    }

    private fun requireArgument(call: MethodCall, key: String): String =
        call.argument<String>(key)?.takeIf(String::isNotBlank)
            ?: throw IllegalArgumentException("$key is required")

    private fun disposeUser() {
        user?.let {
            runCatching { it.logout() }
            runCatching { it.destroy() }
        }
        user = null
        token = ""
        acceptIncomingRtsCalls = false
        incomingRtsDescription = "Rejected by application policy"
        completePendingWithError("disposed", "MIMC user was disposed")
    }

    private fun completePendingWithError(code: String, message: String) {
        val pending = buildList {
            drainPending(pendingCreates, this)
            drainPending(pendingJoins, this)
            drainPending(pendingQuits, this)
            drainPending(pendingDismisses, this)
        }
        pending.forEach { post { it.error(code, message, null) } }
    }

    private fun drainPending(
        source: ConcurrentHashMap<Long, MethodChannel.Result>,
        destination: MutableList<MethodChannel.Result>,
    ) {
        source.forEach { (requestId, pending) ->
            if (source.remove(requestId, pending)) destination.add(pending)
        }
    }

    private fun emit(type: String, data: Map<String, Any?> = emptyMap()) {
        post { eventSink?.success(mapOf("type" to type, "data" to data)) }
    }

    private fun post(block: () -> Unit) {
        if (Looper.myLooper() == Looper.getMainLooper()) block() else mainHandler.post(block)
    }

    private fun messageMap(message: MIMCMessage, channel: String) = mapOf(
        "packetId" to message.packetId,
        "sequence" to message.sequence,
        "timestamp" to message.timestamp,
        "fromAccount" to message.fromAccount,
        "fromResource" to message.fromResource,
        "toAccount" to message.toAccount,
        "toResource" to message.toResource,
        "payload" to message.payload,
        "bizType" to message.bizType,
        "channel" to channel,
    )

    private fun groupMessageMap(message: MIMCGroupMessage, channel: String) = mapOf(
        "packetId" to message.packetId,
        "sequence" to message.sequence,
        "timestamp" to message.timestamp,
        "fromAccount" to message.fromAccount,
        "fromResource" to message.fromResource,
        "topicId" to message.topicId,
        "payload" to message.payload,
        "bizType" to message.bizType,
        "channel" to channel,
    )

    private fun channelMemberMap(member: ChannelUser) = mapOf(
        "appAccount" to member.appAccount,
        "resource" to member.resource,
    )

    private inner class TokenFetcher : MIMCTokenFetcher {
        override fun fetchToken(): String = token
    }

    private inner class StatusListener : MIMCOnlineStatusListener {
        override fun statusChange(
            status: MIMCConstant.OnlineStatus,
            type: String?,
            reason: String?,
            description: String?,
        ) {
            emit(
                "connectionChanged",
                mapOf(
                    "state" to if (status == MIMCConstant.OnlineStatus.ONLINE) "online" else "offline",
                    "reason" to reason,
                    "description" to description,
                ),
            )
            val text = listOf(type, reason, description).joinToString(" ").lowercase()
            if ("token" in text) emit("tokenRefreshRequired")
        }
    }

    private inner class MessageListener : MIMCMessageHandler {
        override fun handleMessage(messages: MutableList<MIMCMessage>): Boolean {
            messages.forEach { emit("message", messageMap(it, "direct")) }
            return true
        }

        override fun handleGroupMessage(messages: MutableList<MIMCGroupMessage>): Boolean {
            messages.forEach { emit("groupMessage", groupMessageMap(it, "group")) }
            return true
        }

        override fun handleUnlimitedGroupMessage(messages: MutableList<MIMCGroupMessage>): Boolean {
            messages.forEach {
                emit("unlimitedGroupMessage", groupMessageMap(it, "unlimitedGroup"))
            }
            return true
        }

        override fun handleServerAck(ack: MIMCServerAck) {
            emit(
                "serverAck",
                mapOf(
                    "packetId" to ack.packetId,
                    "sequence" to ack.sequence,
                    "timestamp" to ack.timestamp,
                    "code" to ack.code,
                    "description" to ack.desc,
                ),
            )
        }

        override fun handleSendMessageTimeout(message: MIMCMessage) =
            emit("sendMessageTimeout", messageMap(message, "direct"))

        override fun handleSendGroupMessageTimeout(message: MIMCGroupMessage) =
            emit("sendGroupMessageTimeout", groupMessageMap(message, "group"))

        override fun handleSendUnlimitedGroupMessageTimeout(message: MIMCGroupMessage) =
            emit(
                "sendUnlimitedGroupMessageTimeout",
                groupMessageMap(message, "unlimitedGroup"),
            )

        override fun onPullNotification(minSequence: Long, maxSequence: Long): Boolean {
            emit(
                "offlinePullNotification",
                mapOf("minSequence" to minSequence, "maxSequence" to maxSequence),
            )
            user?.pull()
            return true
        }

        override fun handleOnlineMessage(message: MIMCMessage) =
            emit("onlineMessage", messageMap(message, "online"))

        override fun handleOnlineMessageAck(ack: MIMCOnlineMessageAck) {
            emit(
                "serverAck",
                mapOf(
                    "packetId" to ack.packetId,
                    "code" to ack.code,
                    "description" to ack.desc,
                ),
            )
        }
    }

    private inner class UnlimitedGroupListener : MIMCUnlimitedGroupHandler {
        override fun handleCreateUnlimitedGroup(
            topicId: Long,
            topicName: String?,
            code: Int,
            description: String?,
            context: Any?,
        ) {
            val requestId = (context as? Number)?.toLong() ?: return
            val pending = pendingCreates.remove(requestId) ?: return
            post {
                if (code == 0) pending.success(topicId)
                else pending.error("uc_create_$code", description, null)
            }
        }

        override fun handleJoinUnlimitedGroup(
            topicId: Long,
            code: Int,
            description: String?,
            context: Any?,
        ) = completeRequest(pendingJoins, context, "uc_join", code, description)

        override fun handleQuitUnlimitedGroup(
            topicId: Long,
            code: Int,
            description: String?,
            context: Any?,
        ) = completeRequest(pendingQuits, context, "uc_quit", code, description)

        override fun handleDismissUnlimitedGroup(
            topicId: Long,
            code: Int,
            description: String?,
            context: Any?,
        ) = completeRequest(pendingDismisses, context, "uc_dismiss", code, description)

        override fun handleDismissUnlimitedGroup(topicId: Long) {
            emit("unlimitedGroupDismissed", mapOf("topicId" to topicId))
        }
    }

    private inner class RtsCallListener : MIMCRtsCallHandler {
        override fun onLaunched(
            fromAccount: String?,
            fromResource: String?,
            callId: Long,
            appContent: ByteArray?,
        ): LaunchedResponse {
            val accepted = acceptIncomingRtsCalls
            val description = incomingRtsDescription
            emit(
                "rtsCallIncoming",
                mapOf(
                    "callId" to callId,
                    "fromAccount" to fromAccount,
                    "fromResource" to fromResource,
                    "appContent" to (appContent ?: ByteArray(0)),
                    "accepted" to accepted,
                ),
            )
            return LaunchedResponse(accepted, description)
        }

        override fun onAnswered(callId: Long, accepted: Boolean, description: String?) =
            emit(
                "rtsCallAnswered",
                mapOf(
                    "callId" to callId,
                    "accepted" to accepted,
                    "description" to description,
                ),
            )

        override fun onClosed(callId: Long, description: String?) =
            emit(
                "rtsCallClosed",
                mapOf("callId" to callId, "description" to description),
            )

        override fun onData(
            callId: Long,
            fromAccount: String?,
            resource: String?,
            data: ByteArray?,
            dataType: RtsDataType?,
            channelType: RtsChannelType?,
        ) = emit(
            "rtsData",
            mapOf(
                "callId" to callId,
                "fromAccount" to fromAccount,
                "fromResource" to resource,
                "payload" to (data ?: ByteArray(0)),
                "dataType" to rtsDataTypeName(dataType),
                "channelType" to rtsChannelTypeName(channelType),
            ),
        )

        override fun onSendDataSuccess(callId: Long, dataId: Int, context: Any?) =
            emitRtsSendResult("rtsSendData", callId, dataId, true, context)

        override fun onSendDataFailure(callId: Long, dataId: Int, context: Any?) =
            emitRtsSendResult("rtsSendData", callId, dataId, false, context)
    }

    private inner class RtsChannelListener : MIMCRtsChannelHandler {
        override fun onCreateChannel(
            identity: Long,
            callId: Long,
            callKey: String?,
            success: Boolean,
            description: String?,
            extra: ByteArray?,
        ) = emit(
            "rtsChannelCreated",
            mapOf(
                "identity" to identity,
                "callId" to callId,
                "callKey" to callKey,
                "success" to success,
                "description" to description,
                "extra" to (extra ?: ByteArray(0)),
            ),
        )

        override fun onJoinChannel(
            callId: Long,
            appAccount: String?,
            resource: String?,
            success: Boolean,
            description: String?,
            extra: ByteArray?,
            members: MutableList<ChannelUser>?,
        ) = emit(
            "rtsChannelJoined",
            mapOf(
                "callId" to callId,
                "appAccount" to appAccount,
                "resource" to resource,
                "success" to success,
                "description" to description,
                "extra" to (extra ?: ByteArray(0)),
                "members" to members.orEmpty().map(::channelMemberMap),
            ),
        )

        override fun onLeaveChannel(
            callId: Long,
            appAccount: String?,
            resource: String?,
            success: Boolean,
            description: String?,
        ) = emit(
            "rtsChannelLeft",
            mapOf(
                "callId" to callId,
                "appAccount" to appAccount,
                "resource" to resource,
                "success" to success,
                "description" to description,
            ),
        )

        override fun onUserJoined(callId: Long, appAccount: String?, resource: String?) =
            emit(
                "rtsChannelUserJoined",
                mapOf(
                    "callId" to callId,
                    "appAccount" to appAccount,
                    "resource" to resource,
                ),
            )

        override fun onUserLeft(callId: Long, appAccount: String?, resource: String?) =
            emit(
                "rtsChannelUserLeft",
                mapOf(
                    "callId" to callId,
                    "appAccount" to appAccount,
                    "resource" to resource,
                ),
            )

        override fun onData(
            callId: Long,
            fromAccount: String?,
            resource: String?,
            data: ByteArray?,
            dataType: RtsDataType?,
        ) = emit(
            "rtsChannelData",
            mapOf(
                "callId" to callId,
                "fromAccount" to fromAccount,
                "fromResource" to resource,
                "payload" to (data ?: ByteArray(0)),
                "dataType" to rtsDataTypeName(dataType),
            ),
        )

        override fun onSendDataSuccess(callId: Long, dataId: Int, context: Any?) =
            emitRtsSendResult("rtsChannelSendData", callId, dataId, true, context)

        override fun onSendDataFailure(callId: Long, dataId: Int, context: Any?) =
            emitRtsSendResult("rtsChannelSendData", callId, dataId, false, context)
    }

    private fun emitRtsSendResult(
        type: String,
        callId: Long,
        dataId: Int,
        success: Boolean,
        context: Any?,
    ) = emit(
        type,
        mapOf(
            "callId" to callId,
            "dataId" to dataId,
            "success" to success,
            "context" to context?.toString(),
        ),
    )

    private fun rtsDataTypeName(type: RtsDataType?): String =
        if (type == RtsDataType.VIDEO) "video" else "audio"

    private fun rtsChannelTypeName(type: RtsChannelType?): String = when (type) {
        RtsChannelType.RELAY -> "relay"
        RtsChannelType.P2P_INTERNET -> "p2pInternet"
        RtsChannelType.P2P_INTRANET -> "p2pIntranet"
        null -> "automatic"
    }

    private fun completeRequest(
        requests: ConcurrentHashMap<Long, MethodChannel.Result>,
        context: Any?,
        operation: String,
        code: Int,
        description: String?,
    ) {
        val requestId = (context as? Number)?.toLong() ?: return
        val pending = requests.remove(requestId) ?: return
        post {
            if (code == 0) pending.success(null)
            else pending.error("${operation}_$code", description, null)
        }
    }

    override fun onListen(arguments: Any?, sink: EventChannel.EventSink) {
        eventSink = sink
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        methodChannel.setMethodCallHandler(null)
        eventChannel.setStreamHandler(null)
        eventSink = null
        disposeUser()
    }

    companion object {
        private const val METHODS_CHANNEL = "dev.flutter_mimc/methods"
        private const val EVENTS_CHANNEL = "dev.flutter_mimc/events"
        private val CAPABILITIES = listOf(
            "message",
            "groupMessage",
            "onlineMessage",
            "unlimitedGroup",
            "offlinePull",
            "realtimeStream",
            "realtimeChannel",
        )
    }
}
