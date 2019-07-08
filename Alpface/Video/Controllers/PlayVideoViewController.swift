//
//  PlayVideoViewController.swift
//  Alpface
//
//  Created by swae on 2018/3/12.
//  Copyright © 2018年 alpface. All rights reserved.
//  处理播放器的播放控制，不含UI

import UIKit
import AVFoundation

//播放器的几种状态
@objc(ALPPlayerState)
enum PlayerState : Int {
    case notKnow       = 0
    case buffering     = 1
    case playing       = 2
    case stopped       = 3
    case paused        = 4
    case failure       = 5
}

@objc(ALPPlayVideoViewControllerDelegate)
protocol PlayVideoViewControllerDelegate: NSObjectProtocol {
    // 播放进度改变时调用
    @objc optional func playVideoViewController(didChangePlayerProgress player:PlayVideoViewController, time: String, progress: Float) -> Void
    // 缓冲进度改变时调用
    @objc optional func playVideoViewController(didChangebufferedProgress player:PlayVideoViewController, loadedTime: Double, bufferedProgress: Float) -> Void
    // 播放状态改变时调用
    @objc optional func playVideoViewController(didChangePlayerState player:PlayVideoViewController, state: PlayerState) -> Void
    // 播放到结束位置调用
    @objc optional func playVideoViewController(didPlayToEnd player:PlayVideoViewController) -> Void
}

@objc(ALPPlayVideoViewController)
class PlayVideoViewController: UIViewController {
    
    fileprivate struct PlayVideoViewControllerKeys {
        static let ALPStatusKeyPath = "status"
        static let ALPLoadedTimeRangesKeyPath = "loadedTimeRanges"
        static let ALPPlaybackBufferEmptyKeyPath = "playbackBufferEmpty"
        static let ALPPlaybackLikelyToKeepUpKeyPath = "playbackLikelyToKeepUp"

    }
    
    // 播放代理对象
    open weak var delegate: PlayVideoViewControllerDelegate?
    // 播放状态， 默认为停止
    open var state : PlayerState = .notKnow {
        didSet {
            if oldValue == state {
                return
            }
            guard let delegate = delegate else {
                return
            }
            if delegate.responds(to: #selector(PlayVideoViewControllerDelegate.playVideoViewController(didChangePlayerState:state:))) {
                delegate.playVideoViewController!(didChangePlayerState: self, state: state)
            }
        }
    }
    // 是否在播放完成后自动播放
    open var shouldLoopPlayWhenPlaybackFinished = true
    
    // 播放的url
    fileprivate var url : URL?
    // 视频缓冲的进度
    open var bufferedProgress : Float = 0.0
    // 视频播放的进度
    open var playerProgress : Float = 0.0
    // 视频总时长
    open var totalDuration : Float = 0.0
    // 是否已消失，当未显示在屏幕上是是不允许播放的
    open var isEndDisplaying : Bool = true
    // 是否是用户暂停播放
    open var isPauseByUser   = false
    // 播放器容器视图
    fileprivate lazy var containerView: VideoPlayerView = {
        let  containerView = VideoPlayerView(frame: .zero)
        containerView.backgroundColor = UIColor.black
        containerView.translatesAutoresizingMaskIntoConstraints = false
        let playerLayer = containerView.layer as! AVPlayerLayer
        playerLayer.videoGravity = .resizeAspectFill //视频填充模式 填充整个view 完美视频iPhonex
        return containerView
    }()
    
    // 播放器对象
    var player: AVPlayer?
    // 播放资源对象
    var playerItem: AVPlayerItem? {
        didSet {
            // playerItem 发生改变时，重置observer
            if oldValue == playerItem  {
                return
            }
            
            removeObserver(playerItem: oldValue)
        }
    }
    // 播放时间观察者
    fileprivate var timeObserver: Any?
    
    // 添加AVPlayerItem的监听集合，防止KVO crash
    fileprivate var observerSet: Set<String> = Set()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        addApplicationObserver()
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
        pause()
    }
    
    
    fileprivate func setupUI(){
        
        view.addSubview(containerView)
        containerView.leadingAnchor.constraint(equalTo: view.leadingAnchor).isActive = true
        containerView.trailingAnchor.constraint(equalTo: view.trailingAnchor).isActive = true
        containerView.bottomAnchor.constraint(equalTo: view.bottomAnchor).isActive = true
        containerView.topAnchor.constraint(equalTo: view.topAnchor).isActive = true

    }
    
    // 将秒转成时间字符串的方法，因为我们将得到秒。
    fileprivate func formatPlayTime(seconds: Float64)->String{
        let min = Int(seconds / 60)
        let sec = Int(seconds.truncatingRemainder(dividingBy: 60))
        return String(format: "%02d:%02d", min, sec)
    }
    
    // 计算当前的缓冲进度
    fileprivate func calculateDownloadProgress(_ playerItem: AVPlayerItem?)-> Float {
        guard let loadedTimeRanges = playerItem?.loadedTimeRanges, let first = loadedTimeRanges.first else {fatalError()}
        // 本次缓冲时间范围
        let timeRange = first.timeRangeValue
        let startSeconds = CMTimeGetSeconds(timeRange.start)//本次缓冲起始时间
        let durationSecound = CMTimeGetSeconds(timeRange.duration)//缓冲时间
        let timeInterval = startSeconds + durationSecound//缓冲总长度
        let duration = playerItem!.duration
        let totalDuration = CMTimeGetSeconds(duration)
        bufferedProgress = Float(timeInterval)/Float(totalDuration)
        if let delegate = delegate {
            if delegate.responds(to: #selector(PlayVideoViewControllerDelegate.playVideoViewController(didChangebufferedProgress:loadedTime:bufferedProgress:))) {
                delegate.playVideoViewController!(didChangebufferedProgress: self, loadedTime: timeInterval, bufferedProgress: bufferedProgress)
            }
        }
        return bufferedProgress
    }
    
    // 播放结束，回到最开始位置，播放按钮显示带播放图标
    @objc func playerItemDidPlayToEnd(notification: Notification){
        player?.seek(to: CMTime.zero, toleranceBefore: CMTime.zero, toleranceAfter: CMTime.zero)
        if let delegate = delegate {
            if delegate.responds(to: #selector(PlayVideoViewControllerDelegate.playVideoViewController(didPlayToEnd:))) {
                delegate.playVideoViewController!(didPlayToEnd: self)
            }
        }
        
        if shouldLoopPlayWhenPlaybackFinished {
            play()
        }
        else {
            // 更新状态
            state = .stopped
            resetPlayer()
        }
    }
    
    // MARK: - Play Control
    // 准备播放一个资源，会请求此资源，但不会立即播放，如要播放需执行play()
    open func preparePlayback(url: URL) {
        let playerItem: AVPlayerItem!
        var needsUpdatePlayer = false
        if self.url == url {
            playerItem = self.playerItem
        }
        else {
            needsUpdatePlayer = true
            playerItem = AVPlayerItem(url: url as URL)
            
        }
        self.url = url
        
        print("播放器准备资源中, url: \(self.url!.absoluteString)")
        self.playerItem = playerItem
        
        // 创建视频播放器视图
        let playerLayer = containerView.layer as! AVPlayerLayer
        if (playerLayer.player == nil) {
            player = AVPlayer(playerItem: playerItem)
            playerLayer.player = player
        }
        else {
            if needsUpdatePlayer == true {
                playerLayer.player?.replaceCurrentItem(with: playerItem)
            }
        }
        
        if state == .notKnow {
            state = .buffering
        }
        
    }

    
    // 自动播放, 当非用户暂停时，或者播放完成后的自动播放
    open func loopPlay() {
        if !isPauseByUser && url != nil {
            if isEndDisplaying == true || // 未显示在屏幕上是不允许播放的
                (state == .playing) || // 正在播放中，就不再重复播放
                (state == .stopped && shouldLoopPlayWhenPlaybackFinished == false)
            {
                return
            }
            play()
        }
    }
    
    // 开始播放
    open func play() {
        if UIApplication.shared.applicationState == .active {
            if player == nil {
                guard let url = url else { return }
                preparePlayback(url: url)
            }
            removeObserver(playerItem: playerItem)
            addObserver()
            if state != .playing && state != .stopped { // 如果是继续播放时，就不重置为buffering
                state = .buffering
            }
            player?.play()
            isPauseByUser = false
            print("开始 url: \(self.url!.absoluteString)")
        }
    }
    
    // 暂停播放
    open func pause(loopPlay isLoop: Bool = false, isFromApplication: Bool = false) {
        // 防止用户触发暂停后，又因不符合播放而暂停，导致无法区分真正暂停的原因
        if self.state == .paused || self.state == .stopped {
            return
        }
        removeObserver(playerItem: playerItem, isFromApplication: isFromApplication)
        player?.pause()
        state = .paused
        isPauseByUser = !isLoop
        if isLoop {
            self.seek(toTime: 0)
        }
        print("暂停 url: \(self.url!.absoluteString)")
    }
    // 播放某个时间点
    open func seek(toTime seconds : Float) {
        guard state != .stopped else { return }
        var second = max(0, seconds)
        second = min(seconds, totalDuration)
        if self.state == .playing || self.state == .buffering {
            pause()
        }
        player?.seek(to: CMTimeMakeWithSeconds(Float64(second), preferredTimescale: Int32(NSEC_PER_SEC)) , completionHandler: { (_) in
    
        })
    }
    
    // 重置播放器
    open func resetPlayer() {
        guard playerItem != nil else { return }
        self.pause()
        removeObserver(playerItem: playerItem)
        self.isPauseByUser = false
        state = .stopped
        NotificationCenter.default.removeObserver(self)
        print("播放器被重置了 url: \(self.url!.absoluteString)")
    }

    deinit {
        resetPlayer()
        player?.replaceCurrentItem(with: nil)
        player = nil
        playerItem = nil
        print("播放器释放了 url: \(self.url!.absoluteString)")
    }
    
}

extension PlayVideoViewController {
    // 移除观察者
    fileprivate func removeObserver(playerItem item: AVPlayerItem?, isFromApplication: Bool = false) {
        guard let playerItem = item else { return }
        safeRemoveObserver(forKeyPath: PlayVideoViewControllerKeys.ALPLoadedTimeRangesKeyPath, playItem: playerItem)
        safeRemoveObserver(forKeyPath: PlayVideoViewControllerKeys.ALPPlaybackBufferEmptyKeyPath, playItem: playerItem)
        safeRemoveObserver(forKeyPath: PlayVideoViewControllerKeys.ALPPlaybackLikelyToKeepUpKeyPath, playItem: playerItem)
        safeRemoveObserver(forKeyPath: PlayVideoViewControllerKeys.ALPStatusKeyPath, playItem: playerItem)
        
        
       
        if let timeObserver = timeObserver {
            player?.removeTimeObserver(timeObserver)
        }
        timeObserver = nil
        NotificationCenter.default.removeObserver(self, name:  Notification.Name.AVPlayerItemDidPlayToEndTime, object: playerItem)
        NotificationCenter.default.removeObserver(self, name: NSNotification.Name.AVPlayerItemPlaybackStalled, object: playerItem)
        if isFromApplication == false {
            self.observerSet.remove(UIApplication.didEnterBackgroundNotification.rawValue)
            NotificationCenter.default.removeObserver(self, name: UIApplication.didEnterBackgroundNotification, object: nil)
            
            self.observerSet.remove(UIApplication.willEnterForegroundNotification.rawValue)
            NotificationCenter.default.removeObserver(self, name: UIApplication.willEnterForegroundNotification, object: nil)
            
            self.observerSet.remove(UIApplication.willResignActiveNotification.rawValue)
            NotificationCenter.default.removeObserver(self, name: UIApplication.willResignActiveNotification, object: nil)
            
            self.observerSet.remove(UIApplication.didBecomeActiveNotification.rawValue)
            NotificationCenter.default.removeObserver(self, name: UIApplication.didBecomeActiveNotification, object: nil)
        }
    }
    
    // 给AVPlayerItem、AVPlayer添加监控
    fileprivate func addObserver(){
        // 为AVPlayerItem添加status属性观察，得到资源准备好，开始播放视频
        safeAddObserver(forKeyPath: PlayVideoViewControllerKeys.ALPStatusKeyPath)
        // 监听AVPlayerItem的loadedTimeRanges属性来监听缓冲进度更新
        safeAddObserver(forKeyPath: PlayVideoViewControllerKeys.ALPLoadedTimeRangesKeyPath)
        safeAddObserver(forKeyPath: PlayVideoViewControllerKeys.ALPPlaybackBufferEmptyKeyPath)
        safeAddObserver(forKeyPath: PlayVideoViewControllerKeys.ALPPlaybackLikelyToKeepUpKeyPath)
        
        addPlayProgressObserver()
        NotificationCenter.default.addObserver(self, selector: #selector(PlayVideoViewController.playerItemDidPlayToEnd(notification:)), name: Notification.Name.AVPlayerItemDidPlayToEndTime, object: playerItem)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(playerItemPlaybackStalled(notification:)),
                                               name: NSNotification.Name.AVPlayerItemPlaybackStalled,
                                               object: playerItem)
        addApplicationObserver()
    }
    
    fileprivate func safeRemoveObserver(forKeyPath keyPath: String, playItem: AVPlayerItem?) {
        guard let playerItem = playItem else { return }
        if observerSet.contains(keyPath) == true {
            playerItem.removeObserver(self, forKeyPath: keyPath)
            observerSet.remove(keyPath)
        }
    }
    fileprivate func safeAddObserver(forKeyPath keyPath: String) {
        guard let playerItem = playerItem else {
            return
        }
        if observerSet.contains(keyPath) == false {
            // 为AVPlayerItem添加status属性观察，得到资源准备好，开始播放视频
            playerItem.addObserver(self, forKeyPath: keyPath, options: .new, context: nil)
            observerSet.insert(PlayVideoViewControllerKeys.ALPStatusKeyPath)
        }
    }
    
    fileprivate func addApplicationObserver() {
        if self.observerSet.contains(UIApplication.didEnterBackgroundNotification.rawValue) == false {
            NotificationCenter.default.addObserver(self,
                                                   selector: #selector(applicationDidEnterBackground),
                                                   name: UIApplication.didEnterBackgroundNotification,
                                                   object: nil)
            self.observerSet.insert(UIApplication.didEnterBackgroundNotification.rawValue)
        }
       
        if self.observerSet.contains(UIApplication.willEnterForegroundNotification.rawValue) == false {
            NotificationCenter.default.addObserver(self,
                                                   selector: #selector(applicationWillEnterForeground),
                                                   name: UIApplication.willEnterForegroundNotification,
                                                   object: nil)
            self.observerSet.insert(UIApplication.willEnterForegroundNotification.rawValue)
        }
       
        if self.observerSet.contains(UIApplication.willResignActiveNotification.rawValue) == false {
            NotificationCenter.default.addObserver(self,
                                                   selector: #selector(applicationWillResignActive),
                                                   name: UIApplication.willResignActiveNotification,
                                                   object: nil)
            self.observerSet.insert(UIApplication.willResignActiveNotification.rawValue)
        }
        if self.observerSet.contains(UIApplication.didBecomeActiveNotification.rawValue) == false {
            NotificationCenter.default.addObserver(self,
                                                   selector: #selector(applicationDidBecomeActive),
                                                   name: UIApplication.didBecomeActiveNotification,
                                                   object: nil)
            self.observerSet.insert(UIApplication.didBecomeActiveNotification.rawValue)
        }
       
    }
    
    // 给播放器添加播放进度更新
    fileprivate func addPlayProgressObserver() {
        if let timeObserver = timeObserver {
            player?.removeTimeObserver(timeObserver)
        }
        // 这里设置每秒执行一次.
        timeObserver =  player?.addPeriodicTimeObserver(forInterval: CMTimeMake(value: Int64(1.0), timescale: Int32(1.0)), queue: DispatchQueue.main) { [weak self](time: CMTime) in
            //CMTimeGetSeconds函数是将CMTime转换为秒，如果CMTime无效，将返回NaN
            let currentTime = CMTimeGetSeconds(time)
            let totalTime = CMTimeGetSeconds(self!.playerItem!.duration)
            if totalTime.isNaN || totalTime.isZero {
                return
            }
            if (self?.isPauseByUser == false) {
                self?.state = .playing;
            }
            // 更新显示的时间和进度条
            let timeStr = self!.formatPlayTime(seconds: CMTimeGetSeconds(time))
            let playProgress = Float(currentTime/totalTime)
            if let delegate = self?.delegate {
                if delegate.responds(to: #selector(PlayVideoViewControllerDelegate.playVideoViewController(didChangePlayerProgress:time:progress:))) {
                    delegate.playVideoViewController!(didChangePlayerProgress: self!, time: timeStr, progress: playProgress)
                }
            }
            
            print("当前播放时间:\(self!.formatPlayTime(seconds: CMTimeGetSeconds(time)))")
        }
    }
    
    
    // MARK: - Observer
    
    @objc fileprivate func applicationWillEnterForeground() {
        let topVC = UIViewController.alp_topViewController()
        if topVC == self {
            loopPlay()
        }
    }
    
    @objc fileprivate func applicationDidEnterBackground() {
        pause(loopPlay: true, isFromApplication: true)
    }
    
    @objc fileprivate func applicationWillResignActive() {
        pause(loopPlay: true, isFromApplication: true)
    }
    
    @objc fileprivate func applicationDidBecomeActive() {
        let topVC = UIViewController.alp_topViewController()
        if topVC == self {
            loopPlay()
        }
    }
    
    @objc fileprivate func playerItemPlaybackStalled(notification: Notification) {
        // 这里网络不好的时候，就会进入，不做处理，会在playbackBufferEmpty里面缓存之后重新播放
    
    }
    
    // 通过KVO监控播放器状态
    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        guard let playerItem = object as? AVPlayerItem  else { return }
        guard let keyPath = keyPath else { return }
        if keyPath == "status" {
            if playerItem.status == .readyToPlay { //当资源准备好播放，那么开始播放视频
                // 视频总时间
                totalDuration = Float(Float64(playerItem.duration.value) / Float64(playerItem.duration.timescale))
                //        let totalDurationString = formatPlayTime(seconds: totalDuration)
                let seconds = CMTimeGetSeconds(playerItem.duration)
                if seconds.isNaN == false {
                    print("准备播放中...，视频总长度:\(String(describing: formatPlayTime(seconds: )))")
                }
            }
            else if playerItem.status == .failed || playerItem.status == .unknown {
                state = .failure
            }
        }
        else if keyPath == "loadedTimeRanges" {
            _  = calculateDownloadProgress(playerItem)
            print("当前加载进度\(bufferedProgress)" )
        }
        else if keyPath == "playbackBufferEmpty" {
            // 监听播放器在缓冲数据的状态
            state = .buffering
            // isPlaybackBufferEmpty这个属性不准，所以检查缓冲的时间
//            if playerItem.isPlaybackBufferEmpty {
//                pause()
//            }
        } else if keyPath == "playbackLikelyToKeepUp" {
            // 缓存足够了，可以播放
            if state == .playing {
                player?.play()
            }
//            state = .playing
            print("缓存足够了，可以播放")
        }
    }
  
    
}
