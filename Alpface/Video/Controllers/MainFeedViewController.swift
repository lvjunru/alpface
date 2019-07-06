//
//  HomeViewController.swift
//  Alpface
//
//  Created by swae on 2018/3/11.
//  Copyright © 2018年 alpface. All rights reserved.
//

import UIKit


@objc(ALPMainFeedViewController)
class MainFeedViewController: HomeRefreshViewController {
    
    
    public var initialPage = 0
    
    public lazy var videoItems: [PlayVideoModel] = {
        let items = [PlayVideoModel]()
        return items
    }()
    
    public var isVisibleInDisplay: Bool = false
    
    
    public lazy var collectionView: GestureCoordinatingCollectionView = {
        let layout = UICollectionViewFlowLayout()
        layout.minimumLineSpacing = 0.0
        layout.minimumInteritemSpacing = 0.0
        layout.scrollDirection = .vertical
        let collectionView = GestureCoordinatingCollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.isPagingEnabled = true
        collectionView.bounces = false
        collectionView.showsHorizontalScrollIndicator = false
        collectionView.showsVerticalScrollIndicator = false
        collectionView.register(MainFeedViewCell.classForCoder(), forCellWithReuseIdentifier: "MainFeedViewCell")
        collectionView.backgroundColor = UIColor.clear
        return collectionView
    }()
    
    public func displayViewController() -> UIViewController? {
        if let cell = collectionView.visibleCells.first as? MainFeedViewCell {
            return cell.viewController.playVideoVc
        }
        return nil
    }
    
    public func displayVideoItem() -> VideoItem? {
        if let cell = collectionView.visibleCells.first as? MainFeedViewCell {
            guard let model = cell.model else {
                return nil
            }
            guard let video = model.model as? VideoItem else {
                return nil
            }
            return video
        }
        return nil
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view.
        setupUI()
        
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        self.isVisibleInDisplay = true
        displayViewController()?.beginAppearanceTransition(true, animated: animated)
    }
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        displayViewController()?.endAppearanceTransition()
        self.updatePlayControl()
        DispatchQueue.main.async {
            UIApplication.shared.setNeedsStatusBarAppearanceUpdate()
        }
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        displayViewController()?.beginAppearanceTransition(false, animated: true)
        // 所有model停止播放
        for videoItem in videoItems {
            videoItem.isAllowPlay = false
        }
    }
    
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        displayViewController()?.endAppearanceTransition()
        self.isVisibleInDisplay = false
        // 所有model停止播放
        for videoItem in videoItems {
            videoItem.isAllowPlay = false
        }
    }
    
    
    public func show(page index: Int, animated: Bool) {
        if collectionView.indexPathsForVisibleItems.first?.row == index {
            return
        }
        collectionView .scrollToItem(at: IndexPath.init(row: index, section: 0), at: .centeredVertically, animated: animated)
    }
    
    public func updatePlayControl() {
        var vidbleIndexPath = collectionView.indexPathsForVisibleItems.first
        if vidbleIndexPath == nil {
            vidbleIndexPath = IndexPath.init(row: 0, section: 0)
        }
        if vidbleIndexPath!.row >= videoItems.count {
            return
        }
        
        // 取出当前显示的model,继续播放
        let model = videoItems[vidbleIndexPath!.row]
        // 所有model停止播放
        for videoItem in videoItems {
            if model != videoItem {
                videoItem.isAllowPlay = false
            }
        }
        
        if isVisibleInDisplay == false {
            model.isAllowPlay = false
            return
        }
        
        model.isAllowPlay = true
    }
    
    fileprivate func setupUI() {
        view.backgroundColor = UIColor.clear
        automaticallyAdjustsScrollViewInsets = false
        if #available(iOS 11.0, *) {
            collectionView.contentInsetAdjustmentBehavior = .never
        }
        view.addSubview(collectionView)
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor).isActive = true
        collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor).isActive = true
        collectionView.topAnchor.constraint(equalTo: view.topAnchor).isActive = true
        // iPhone x 系列 底部内容显示在安全区域以上
        // 其他系列 底部内容显示在屏幕底部以上，tabBar透明显示，可以看到全屏内容
        if #available(iOS 11.0, *), AppUtils.isIPhoneX() {
            collectionView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor).isActive = true
        } else {
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor).isActive = true
        }
        
        
        setupNavigation()
    }
    
    fileprivate func setupNavigation() {
        // 设置导航栏标题属性：设置标题字体
        let font = UIFont(name: "MedulaOne-Regular", size: 20.0)
        navigationController?.navigationBar.titleTextAttributes = [NSAttributedString.Key.font: font ?? UIFont.systemFont(ofSize: 20.0), NSAttributedString.Key.foregroundColor: UIColor.white]
        
        // 设置导航栏前景色：设置item指示色
        navigationController?.navigationBar.tintColor = UIColor.white
        
        // 设置导航栏半透明
        navigationController?.navigationBar.isTranslucent = true
        
        // 设置导航栏背景图片
        navigationController?.navigationBar.setBackgroundImage(UIImage(), for: UIBarMetrics.default)
        
        // 设置导航栏阴影图片
        navigationController?.navigationBar.shadowImage = UIImage()
    }
    
    @objc fileprivate func afterRefresher(){
        
        loadPosts()
    }
    
    fileprivate func loadPosts(){
        //        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
        //            self.refreshControl.endRefreshing()
        //        }
    }
    
}



extension MainFeedViewController {
    override var preferredStatusBarStyle: UIStatusBarStyle {
        return .lightContent
    }
    
    override var prefersStatusBarHidden: Bool {
        return true
    }
    
    override var childForStatusBarStyle: UIViewController? {
        return nil
    }
}

extension MainFeedViewController : UICollectionViewDataSource, UICollectionViewDelegate, UICollectionViewDelegateFlowLayout {
    
    func numberOfSections(in collectionView: UICollectionView) -> Int {
        return 1
    }
    
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return videoItems.count
    }
    
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "MainFeedViewCell", for: indexPath) as! MainFeedViewCell
        let c1: CGFloat = CGFloat(arc4random_uniform(256))/255.0
        let c2: CGFloat = CGFloat(arc4random_uniform(256))/255.0
        let c3: CGFloat = CGFloat(arc4random_uniform(256))/255.0
        
        let model = videoItems[indexPath.row]
        cell.model = model
        cell.contentView.backgroundColor = UIColor.init(red: c1, green: c2, blue: c3, alpha: 1.0)
        cell.viewController.interactionController.delegate = self
        return cell
    }
    
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        
        return collectionView.frame.size
    }
    
    /// cell 完全离开屏幕后调用
    func collectionView(_ collectionView: UICollectionView, didEndDisplaying cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
        
        self.updatePlayControl()
    }
    
    /// cell 即将显示在屏幕时调用
    func collectionView(_ collectionView: UICollectionView, willDisplay cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
        if initialPage > 0 {
            show(page: initialPage, animated: false)
            initialPage = 0
        }
    }
    
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        //        let offset = scrollView.contentOffset.y
        //        if offset < -100 {
        //            collectionView.refreshControl?.tintColor = UIColor.white
        //            collectionView.refreshControl?.attributedTitle = NSAttributedString(string: "现在可以松手了", attributes: [.foregroundColor : UIColor.orange])
        //            collectionView.refreshControl?.backgroundColor = UIColor.darkGray
        //        } else {
        //            collectionView.refreshControl?.tintColor = UIColor.white
        //            collectionView.refreshControl?.attributedTitle = NSAttributedString(string: "下拉刷新...", attributes: [.foregroundColor : UIColor.orange])
        //            collectionView.refreshControl?.backgroundColor = UIColor.darkGray
        //        }
    }
    
}

extension MainFeedViewController: PlayInteractionViewControllerDelegate {
    func playInteractionViewController(playInteraction controller: PlayInteractionViewController, didClickUserAvatarFrom video: VideoItem) {
        
    }
}

extension MainFeedViewController {
    
    /// 关闭appearance callbacks的自动传递的特性呢
    //    override var shouldAutomaticallyForwardAppearanceMethods: Bool {
    //        return false
    //    }
    
}
