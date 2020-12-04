//
//  ViewController.swift
//  Video Stitch
//
//  Created by Konrad Winkowski on 10/22/20.
//

import UIKit
import AVFoundation
import AVKit
import Photos
import MobileCoreServices
import MediaPlayer

enum CameraDuration: CaseIterable {
    case five
    case ten
    case twenty
    case manual

    var duration: TimeInterval {
        switch self {
        case .five:
            return 5
        case .ten:
            return 10
        case .twenty:
            return 20
        case .manual:
            return 0
        }
    }

    var strValue: String {
        switch self {
        case .five:
            return "5 sec"
        case .ten:
            return "10 sec"
        case .twenty:
            return "20 sec"
        case .manual:
            return "manual"
        }
    }
}

enum TimeBetweenDuration: CaseIterable {
    case two
    case ten
    case thirty
    case manual

    var countdown: Int {
        switch self {
        case .two:
            return 2
        case .ten:
            return 10
        case .thirty:
            return 30
        case .manual:
            return 0
        }
    }

    var strValue: String {
        switch self {
        case .two:
            return "2 sec"
        case .ten:
            return "10 sec"
        case .thirty:
            return "30 sec"
        case .manual:
            return "manual"
        }
    }
}

enum CameraControllerError: Error {
    case captureSessionAlreadyRunning
    case captureSessionIsMissing
    case inputsAreInvalid
    case invalidOperation
    case noCamerasAvailable
    case unknown
}

enum CameraPosition {
    case front
    case rear
}

class ViewController: UIViewController, AVCaptureFileOutputRecordingDelegate {

    @IBOutlet weak var hudContainer: UIView!
    @IBOutlet weak var startButton: UIButton!
    @IBOutlet weak var exportButton: UIButton!
    @IBOutlet weak var flipCameraButton: UIButton!

    @IBOutlet weak var durationContainer: UIView!
    @IBOutlet weak var durationLabel: UILabel!

    @IBOutlet weak var timeBetweenContainer: UIView!
    @IBOutlet weak var timeBetweenLabel: UILabel!
    @IBOutlet weak var infoLabel: UILabel!

    @IBOutlet weak var previewScrollView: UIScrollView!
    @IBOutlet weak var animatedDurationView: AnimatedDurationView!

    @IBOutlet weak var audioContainerView: UIView!
    @IBOutlet weak var audioImageView: UIImageView!
    @IBOutlet weak var audioArtistLabel: UILabel!
    @IBOutlet weak var audioTitleLabel: UILabel!
    @IBOutlet weak var workingContainerView: UIVisualEffectView!

    private var audioAsset: URL?
    private var song: MPMediaItem? {
        didSet {
            updateSongInfo()
        }
    }

    private var cameraPosition: CameraPosition = .rear {
        didSet {
            flipCamera()
        }
    }

    private var recordingDuration: Int = 0
    private var stepDuration: CameraDuration = .five {
        didSet {
            updateHudInfo()
        }
    }

    private var timeBetweenCountdown: Int = 0
    private var timeBetweenDuration: TimeBetweenDuration = .ten {
        didSet {
            updateHudInfo()
        }
    }

    private var autoStartNext: Bool = true

    private var updateTimer: Timer?
    private var recordingTimer: Timer?

    let captureSession = AVCaptureSession()
    let movieOutput = AVCaptureMovieFileOutput()
    var previewLayer: AVCaptureVideoPreviewLayer!
    var activeInput: AVCaptureDeviceInput!
    var outputURL: URL!
    var videos: [URL] = []

    override func viewDidLoad() {
        super.viewDidLoad()

        durationContainer.layer.cornerRadius = 5.0
        timeBetweenContainer.layer.cornerRadius = 5.0
        audioContainerView.layer.cornerRadius = 5.0
        audioImageView.layer.cornerRadius = 5.0
        startButton.layer.cornerRadius = startButton.bounds.width * 0.5
        previewScrollView.subviews.forEach { $0.removeFromSuperview() }

        if setupSession() {
            setupPreview()
            startSession()
        }

        updateHudInfo()
    }

    func setupPreview() {
        // Configure previewLayer
        previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
        previewLayer.frame = view.bounds
        previewLayer.videoGravity = AVLayerVideoGravity.resizeAspectFill
        view.layer.insertSublayer(previewLayer, below: hudContainer.layer)
    }

    //MARK:- Setup Camera
    func setupSession() -> Bool {

        captureSession.sessionPreset = AVCaptureSession.Preset.high

        // Setup Camera
        let camera = AVCaptureDevice.default(for: AVMediaType.video)!

        do {

            let input = try AVCaptureDeviceInput(device: camera)

            if captureSession.canAddInput(input) {
                captureSession.addInput(input)
                activeInput = input
            }
        } catch {
            print("Error setting device video input: \(error)")
            return false
        }

        // Setup Microphone
        let microphone = AVCaptureDevice.default(for: AVMediaType.audio)!

        do {
            let micInput = try AVCaptureDeviceInput(device: microphone)
            if captureSession.canAddInput(micInput) {
                captureSession.addInput(micInput)
            }
        } catch {
            print("Error setting device audio input: \(error)")
            return false
        }


        // Movie output
        if captureSession.canAddOutput(movieOutput) {
            captureSession.addOutput(movieOutput)
        }

        return true
    }

    func setupCaptureMode(_ mode: Int) {
        // Video Mode

    }

    //MARK:- Camera Session
    func startSession() {
        if !captureSession.isRunning {
            videoQueue().async {
                self.captureSession.startRunning()
            }
        }
    }

    func stopSession() {
        if captureSession.isRunning {
            videoQueue().async {
                self.captureSession.stopRunning()
            }
        }
    }

    // MARK: - shows the default media picker
    @IBAction func didTapAddAudio(_ sender: Any) {
        let mediaPickerController = MPMediaPickerController(mediaTypes: .any)
        mediaPickerController.delegate = self
        mediaPickerController.prompt = "Select Audio"
        present(mediaPickerController, animated: true, completion: nil)
    }

    @IBAction func didTapStartButton(_ sender: Any) {
        startRecording()
    }

    @IBAction func didTapExportButton(_ sender: Any) {
        workingContainerView.isHidden = false
        startExport()
    }

    @IBAction func didTapFlipCamera(_ sender: Any) {
        switch cameraPosition {
        case .front:
            cameraPosition = .rear
        case .rear:
            cameraPosition = .front
        }
    }

    @IBAction func didTapDuration(_ sender: Any) {
        guard videos.isEmpty else { return }
        showDurationOptions(with: durationContainer)
    }

    @IBAction func didTapTimeBetween(_ sender: Any) {
        guard videos.isEmpty else { return }
        showTimeBetweenOptions(with: timeBetweenContainer)
    }

    private func updateSongInfo() {
        guard let song = self.song else {
            audioContainerView.isHidden = true
            return
        }
        audioContainerView.isHidden = false
        audioTitleLabel.text = song.title
        audioArtistLabel.text = song.albumArtist
        audioImageView.image = song.artwork?.image(at: CGSize(width: audioImageView.bounds.width,
                                                              height: audioImageView.bounds.height))
    }

    private func updateHudInfo() {
        durationLabel.text = stepDuration.strValue
        timeBetweenLabel.text = timeBetweenDuration.strValue
    }

    func videoQueue() -> DispatchQueue {
        return DispatchQueue.main
    }

    func currentVideoOrientation() -> AVCaptureVideoOrientation {
        var orientation: AVCaptureVideoOrientation

        switch UIDevice.current.orientation {
        case .portrait:
            orientation = AVCaptureVideoOrientation.portrait
        case .landscapeRight:
            orientation = AVCaptureVideoOrientation.landscapeLeft
        case .portraitUpsideDown:
            orientation = AVCaptureVideoOrientation.portraitUpsideDown
        default:
            orientation = AVCaptureVideoOrientation.landscapeRight
        }

        return orientation
    }

    private func startExport() {
        AVMutableComposition().mergeVideo(videos) { (url, error) in
            AVMutableComposition().watermark(url: url!, image: UIImage(named: "logo_color_text_png")!) { (url, error) in

                if let audioAsset = self.audioAsset {
                    AVMutableComposition().mergeAudio(videoUrl: url!, audioUrl: audioAsset) { (url, error) in
                        print(error)
                        print(url)

                        PHPhotoLibrary.shared().performChanges({
                            PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url!)
                        }) { saved, error in
                            if saved {
                                print("Your video was successfully saved")
                            }
                        }

                        let player = AVPlayer(url: url!)
                        let playerViewController = AVPlayerViewController()
                        playerViewController.player = player
                        self.present(playerViewController, animated: true) {
                            playerViewController.player!.play()
                        }
                    }
                } else {
                    print(error)
                    print(url)

                    PHPhotoLibrary.shared().performChanges({
                        PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url!)
                    }) { saved, error in
                        if saved {
                            print("Your video was successfully saved")
                        }
                    }

                    let player = AVPlayer(url: url!)
                    let playerViewController = AVPlayerViewController()
                    playerViewController.player = player
                    self.present(playerViewController, animated: true) {
                        playerViewController.player!.play()
                    }
                }
            }
        }
    }

    @objc func startCapture() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        startRecording()
    }

    func tempURL() -> URL? {
        let directory = NSTemporaryDirectory() as NSString

        if directory != "" {
            let path = directory.appendingPathComponent(NSUUID().uuidString + ".mp4")
            return URL(fileURLWithPath: path)
        }

        return nil
    }

    func startRecording() {
        guard updateTimer == nil else {
            startButton.setTitle("Start", for: .normal)
            infoLabel.text = nil
            updateTimer?.invalidate()
            updateTimer = nil
            recordingTimer?.invalidate()
            recordingTimer = nil
            return
        }

        if movieOutput.isRecording == false {
            startButton.setTitle("Stop", for: .normal)
            let connection = movieOutput.connection(with: AVMediaType.video)

            if connection?.isVideoOrientationSupported == true {
                connection?.videoOrientation = currentVideoOrientation()
            }

            if connection?.isVideoStabilizationSupported == true {
                connection?.preferredVideoStabilizationMode = AVCaptureVideoStabilizationMode.auto
            }

            let device = activeInput.device

            if (device.isSmoothAutoFocusSupported) {
                do {
                    try device.lockForConfiguration()
                    device.isSmoothAutoFocusEnabled = false
                    device.unlockForConfiguration()
                } catch {
                    print("Error setting configuration: \(error)")
                }
            }

            outputURL = tempURL()

            if timeBetweenDuration == .manual {
                recordVideo()
            } else {
                startRecordingStartTimer()
            }
        } else {
            startButton.setTitle("Start", for: .normal)
            stopRecording()
        }
    }

    func stopRecording() {
        if movieOutput.isRecording == true {
            movieOutput.stopRecording()
        }
    }

    private func flipCamera() {
        guard let current = captureSession.inputs.first else {
            return
        }
        captureSession.removeInput(current)
        switch cameraPosition {
        case .front:
            guard let device = cameraWithPosition(position: .front) else { return }
            guard let input = try? AVCaptureDeviceInput(device: device) else { return }
            if captureSession.canAddInput(input) {
                captureSession.addInput(input)
            }
        case .rear:
            guard let device = cameraWithPosition(position: .back) else { return }
            guard let input = try? AVCaptureDeviceInput(device: device) else { return }
            if captureSession.canAddInput(input) {
                captureSession.addInput(input)
            }
        }
    }

    func cameraWithPosition(position: AVCaptureDevice.Position) -> AVCaptureDevice? {
        switch position {
        case .front:
            return AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front)
        case .back:
            return AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
        default:
            return nil
        }
    }

    private func startRecordingDurationTimer() {
        animatedDurationView.setup(with: stepDuration.duration)
        recordingTimer = Timer.scheduledTimer(withTimeInterval: stepDuration.duration, repeats: true, block: { (_) in
            self.recordingTimer?.invalidate()
            self.recordingTimer = nil
            self.startRecording()
        })
    }

    private func startRecordingStartTimer() {
        timeBetweenCountdown = timeBetweenDuration.countdown
        infoLabel.text = "Starting in \(self.timeBetweenCountdown)"
        updateTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true, block: { (_) in
            guard self.timeBetweenCountdown != 1 else {
                self.recordVideo()
                self.updateTimer?.invalidate()
                self.updateTimer = nil
                self.infoLabel.text = nil
                return
            }
            self.timeBetweenCountdown -= 1
            self.infoLabel.text = "Starting in \(self.timeBetweenCountdown)"
        })
    }

    private func recordVideo() {
        hudContainer.isHidden = true
        movieOutput.startRecording(to: outputURL, recordingDelegate: self)
        if stepDuration != .manual {
            startRecordingDurationTimer()
        }
    }

    func capture(_ captureOutput: AVCaptureFileOutput!, didStartRecordingToOutputFileAt fileURL: URL!, fromConnections connections: [Any]!) {
        print(#function)
    }

    func fileOutput(_ output: AVCaptureFileOutput,
                    didFinishRecordingTo outputFileURL: URL,
                    from connections: [AVCaptureConnection], error: Error?) {
        hudContainer.isHidden = false
        animatedDurationView.end()
        if (error != nil) {
            print("Error recording movie: \(error!.localizedDescription)")
        } else {
            let videoRecorded = outputURL! as URL
            videos.append(videoRecorded)
            if let thumbnail = getThumbnailImage(forUrl: videoRecorded) {
                appendThumbnail(image: thumbnail)
            }
        }

        if autoStartNext && timeBetweenDuration != .manual {
            startRecording()
        }
    }

    func exportDidFinish(_ session: AVAssetExportSession) {
        // 2
        guard
            session.status == AVAssetExportSession.Status.completed,
            let outputURL = session.outputURL
        else { return }

        // 3
        let saveVideoToPhotos = {
            // 4
            let changes: () -> Void = {
                PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: outputURL)
            }
            PHPhotoLibrary.shared().performChanges(changes) { saved, error in
                DispatchQueue.main.async {
                    let success = saved && (error == nil)
                    let title = success ? "Success" : "Error"
                    let message = success ? "Video saved" : "Failed to save video"

                    let alert = UIAlertController(
                        title: title,
                        message: message,
                        preferredStyle: .alert)
                    alert.addAction(UIAlertAction(
                                        title: "OK",
                                        style: UIAlertAction.Style.cancel,
                                        handler: nil))
                    self.present(alert, animated: true, completion: nil)
                }
            }
        }

        // 5
        if PHPhotoLibrary.authorizationStatus() != .authorized {
            PHPhotoLibrary.requestAuthorization { status in
                if status == .authorized {
                    saveVideoToPhotos()
                }
            }
        } else {
            saveVideoToPhotos()
        }
    }

    private func appendThumbnail(image: UIImage) {
        let imageView = UIImageView(frame: CGRect(x: (CGFloat(videos.count - 1) * previewScrollView.bounds.height) + 2,
                                                  y: 0,
                                                  width: previewScrollView.bounds.height,
                                                  height: previewScrollView.bounds.height))
        imageView.contentMode = .scaleAspectFill
        imageView.image = image
        previewScrollView.addSubview(imageView)
    }

    private func getThumbnailImage(forUrl url: URL) -> UIImage? {
        let asset: AVAsset = AVAsset(url: url)
        let imageGenerator = AVAssetImageGenerator(asset: asset)
        imageGenerator.appliesPreferredTrackTransform = true

        do {
            let thumbnailImage = try imageGenerator.copyCGImage(at: CMTimeMake(value: 1, timescale: 60), actualTime: nil)
            return UIImage(cgImage: thumbnailImage)
        } catch let error {
            print(error)
        }

        return nil
    }

    private func showDurationOptions(with sender: UIView) {
        let sheet = UIAlertController(title: "Clip Duration", message: nil, preferredStyle: .actionSheet)
        CameraDuration.allCases.forEach { (duration) in
            sheet.addAction(UIAlertAction(title: duration.strValue, style: .default, handler: { (_) in
                self.stepDuration = duration
            }))
        }

        if UIDevice.current.userInterfaceIdiom == .pad {
            sheet.popoverPresentationController?.sourceView = view
            sheet.popoverPresentationController?.sourceRect = sender.bounds
        }

        present(sheet, animated: true)
    }

    private func showTimeBetweenOptions(with sender: UIView) {
        let sheet = UIAlertController(title: "Setup Duration", message: nil, preferredStyle: .actionSheet)
        TimeBetweenDuration.allCases.forEach { (duration) in
            sheet.addAction(UIAlertAction(title: duration.strValue, style: .default, handler: { (_) in
                self.timeBetweenDuration = duration
            }))
        }

        if UIDevice.current.userInterfaceIdiom == .pad {
            sheet.popoverPresentationController?.sourceView = view
            sheet.popoverPresentationController?.sourceRect = sender.bounds
        }

        present(sheet, animated: true)
    }
}

extension ViewController: MPMediaPickerControllerDelegate {
    // MARK: adding audio
    func mediaPicker(
      _ mediaPicker: MPMediaPickerController,
      didPickMediaItems mediaItemCollection: MPMediaItemCollection
    ) {
      dismiss(animated: true) {
        let selectedSongs = mediaItemCollection.items
        guard let song = selectedSongs.first else { return }

        self.song = song

        guard let url = song.value(forProperty: MPMediaItemPropertyAssetURL) as? URL else {
            let alert = UIAlertController(
              title: "Asset Not Available",
              message: "Audio Not Loaded",
              preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .cancel, handler: nil))
            self.present(alert, animated: true, completion: nil)
            return
        }
        self.audioAsset = url
      }
    }

    func mediaPickerDidCancel(_ mediaPicker: MPMediaPickerController) {
      dismiss(animated: true, completion: nil)
    }
}

extension AVMutableComposition {

    func addAudioTrack(composition: AVMutableComposition, videoUrl: URL) {
        let videoUrlAsset = AVURLAsset(url: videoUrl, options: nil)
        let audioTracks = videoUrlAsset.tracks(withMediaType: AVMediaType.audio)
        let compositionAudioTrack:AVMutableCompositionTrack = composition.addMutableTrack(withMediaType: AVMediaType.audio, preferredTrackID: CMPersistentTrackID())!
        for audioTrack in audioTracks {
            try! compositionAudioTrack.insertTimeRange(audioTrack.timeRange, of: audioTrack, at: CMTime.zero)
        }
    }

    private func resolutionForLocalVideo(url: URL) -> CGSize? {
        guard let track = AVURLAsset(url: url).tracks(withMediaType: AVMediaType.video).first else { return nil }
        let size = track.naturalSize.applying(track.preferredTransform)
        return CGSize(width: abs(size.width), height: abs(size.height))
    }

    func watermark(url: URL, image: UIImage, completion: @escaping (_ url: URL?, _ error: Error?) -> Void) {
        let videoUrlAsset = AVURLAsset(url: url, options: nil)

        let mutableComposition = AVMutableComposition()
        let videoAssetTrack = videoUrlAsset.tracks(withMediaType: AVMediaType.video).first!
        let videoCompositionTrack = mutableComposition.addMutableTrack(withMediaType: AVMediaType.video, preferredTrackID: kCMPersistentTrackID_Invalid)
        videoCompositionTrack?.preferredTransform = videoAssetTrack.preferredTransform
        try! videoCompositionTrack?.insertTimeRange(CMTimeRange(start:CMTime.zero, duration:videoAssetTrack.timeRange.duration), of: videoAssetTrack, at: CMTime.zero)

        let videoSize = resolutionForLocalVideo(url: url) ?? (videoCompositionTrack?.naturalSize)!
        addAudioTrack(composition: mutableComposition, videoUrl: url)

        let frame = CGRect(x: 0.0, y: 0.0, width: videoSize.width, height: videoSize.height)
        let imageLayer = CALayer()
        imageLayer.contents = image.cgImage
        imageLayer.frame = CGRect(x: 0.0, y: 0.0, width:150, height:150)

        let videoLayer = CALayer()
        videoLayer.frame = frame
        let animationLayer = CALayer()
        animationLayer.frame = frame
        animationLayer.addSublayer(videoLayer)
        animationLayer.addSublayer(imageLayer)

        let videoComposition = AVMutableVideoComposition(propertiesOf: (videoCompositionTrack?.asset!)!)
        videoComposition.animationTool = AVVideoCompositionCoreAnimationTool(postProcessingAsVideoLayer: videoLayer, in: animationLayer)
        videoComposition.renderSize = videoSize

        let documentDirectory = NSSearchPathForDirectoriesInDomains(FileManager.SearchPathDirectory.cachesDirectory, FileManager.SearchPathDomainMask.userDomainMask, true).first!
        let documentDirectoryUrl = URL(fileURLWithPath: documentDirectory)
        let destinationFilePath = documentDirectoryUrl.appendingPathComponent(NSUUID().uuidString + ".mp4")

        do {
            if FileManager.default.fileExists(atPath: destinationFilePath.path) {
                try FileManager.default.removeItem(at: destinationFilePath)
            }
        } catch {
            completion(nil, error)
            return
        }

        let exportSession = AVAssetExportSession( asset: mutableComposition, presetName: AVAssetExportPresetHighestQuality)!

        exportSession.videoComposition = videoComposition
        exportSession.outputURL = destinationFilePath
        exportSession.outputFileType = AVFileType.mp4
        exportSession.exportAsynchronously { [weak exportSession] in
            if let strongExportSession = exportSession {
                DispatchQueue.main.async {
                    completion(strongExportSession.outputURL!, nil)
                }
            }
        }
    }

    // MARK: merging audio on top of video
    func mergeAudio(videoUrl: URL, audioUrl: URL, completion: @escaping (_ url: URL?, _ error: Error?) -> Void) {
        var mutableCompositionVideoTrack = [AVMutableCompositionTrack]()
        var mutableCompositionAudioTrack = [AVMutableCompositionTrack]()
        var mutableCompositionAudioOfVideoTrack = [AVMutableCompositionTrack]()

        //start merge

        let aVideoAsset = AVAsset(url: videoUrl)
        let aAudioAsset = AVAsset(url: audioUrl)

        let compositionAddVideo = addMutableTrack(withMediaType: AVMediaType.video,
                                                                 preferredTrackID: kCMPersistentTrackID_Invalid)

        let compositionAddAudio = addMutableTrack(withMediaType: AVMediaType.audio,
                                                                 preferredTrackID: kCMPersistentTrackID_Invalid)

        let compositionAddAudioOfVideo = addMutableTrack(withMediaType: AVMediaType.audio,
                                                                        preferredTrackID: kCMPersistentTrackID_Invalid)

        let aVideoAssetTrack: AVAssetTrack = aVideoAsset.tracks(withMediaType: AVMediaType.video)[0]
        let aAudioOfVideoAssetTrack: AVAssetTrack? = aVideoAsset.tracks(withMediaType: AVMediaType.audio).first
        let aAudioAssetTrack: AVAssetTrack = aAudioAsset.tracks(withMediaType: AVMediaType.audio)[0]

        // Default must have tranformation
        compositionAddVideo?.preferredTransform = aVideoAssetTrack.preferredTransform

        mutableCompositionVideoTrack.append(compositionAddVideo!)
        mutableCompositionAudioTrack.append(compositionAddAudio!)
        mutableCompositionAudioOfVideoTrack.append(compositionAddAudioOfVideo!)

        do {
            try mutableCompositionVideoTrack[0].insertTimeRange(CMTimeRangeMake(start: CMTime.zero,
                                                                                duration: aVideoAssetTrack.timeRange.duration),
                                                                of: aVideoAssetTrack,
                                                                at: CMTime.zero)

            //In my case my audio file is longer then video file so i took videoAsset duration
            //instead of audioAsset duration
            try mutableCompositionAudioTrack[0].insertTimeRange(CMTimeRangeMake(start: CMTime.zero,
                                                                                duration: aVideoAssetTrack.timeRange.duration),
                                                                of: aAudioAssetTrack,
                                                                at: CMTime.zero)

            // adding audio (of the video if exists) asset to the final composition
            if let aAudioOfVideoAssetTrack = aAudioOfVideoAssetTrack {
                try mutableCompositionAudioOfVideoTrack[0].insertTimeRange(CMTimeRangeMake(start: CMTime.zero,
                                                                                           duration: aVideoAssetTrack.timeRange.duration),
                                                                           of: aAudioOfVideoAssetTrack,
                                                                           at: CMTime.zero)
            }
        } catch {
            print(error.localizedDescription)
        }
        let documentDirectory = NSSearchPathForDirectoriesInDomains(FileManager.SearchPathDirectory.cachesDirectory, FileManager.SearchPathDomainMask.userDomainMask, true).first!
        let documentDirectoryUrl = URL(fileURLWithPath: documentDirectory)
        let destinationFilePath = documentDirectoryUrl.appendingPathComponent(NSUUID().uuidString + ".mp4")

        let exportSession = AVAssetExportSession(asset: self, presetName: AVAssetExportPresetHighestQuality)!
        exportSession.outputURL = destinationFilePath
        exportSession.outputFileType = AVFileType.mp4
        exportSession.shouldOptimizeForNetworkUse = true
        exportSession.exportAsynchronously { [weak exportSession] in
            if let strongExportSession = exportSession {
                DispatchQueue.main.async {
                    completion(strongExportSession.outputURL!, nil)
                }
            }
        }
    }

    func mergeVideo(_ urls: [URL], completion: @escaping (_ url: URL?, _ error: Error?) -> Void) {
        guard let documentDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            completion(nil, nil)
            return
        }

        let outputURL = documentDirectory.appendingPathComponent("mergedVideo_\(Date().timeIntervalSince1970).mp4")

        // If there is only one video, we dont to touch it to save export time.
        if let url = urls.first, urls.count == 1 {
            do {
                try FileManager().copyItem(at: url, to: outputURL)
                completion(outputURL, nil)
            } catch let error {
                completion(nil, error)
            }
            return
        }

        let maxRenderSize = CGSize(width: 1280.0, height: 720.0)
        var currentTime = CMTime.zero
        var renderSize = CGSize.zero
        // Create empty Layer Instructions, that we will be passing to Video Composition and finally to Exporter.
        var instructions = [AVMutableVideoCompositionInstruction]()

        urls.enumerated().forEach { index, url in
            let asset = AVAsset(url: url)
            let assetTrack = asset.tracks.first!

            // Create instruction for a video and append it to array.
            let instruction = AVMutableComposition.instruction(assetTrack, asset: asset, time: currentTime, duration: assetTrack.timeRange.duration, maxRenderSize: maxRenderSize)
            instructions.append(instruction.videoCompositionInstruction)

            // Set render size (orientation) according first video.
            if index == 0 {
                renderSize = instruction.isPortrait ? CGSize(width: maxRenderSize.height, height: maxRenderSize.width) : CGSize(width: maxRenderSize.width, height: maxRenderSize.height)
            }

            do {
                let timeRange = CMTimeRangeMake(start: .zero, duration: assetTrack.timeRange.duration)
                // Insert video to Mutable Composition at right time.
                try insertTimeRange(timeRange, of: asset, at: currentTime)
                currentTime = CMTimeAdd(currentTime, assetTrack.timeRange.duration)
            } catch let error {
                completion(nil, error)
            }
        }

        // Create Video Composition and pass Layer Instructions to it.
        let videoComposition = AVMutableVideoComposition()
        videoComposition.instructions = instructions
        // Do not forget to set frame duration and render size. It will crash if you dont.
        videoComposition.frameDuration = CMTimeMake(value: 1, timescale: 30)
        videoComposition.renderSize = renderSize

        guard let exporter = AVAssetExportSession(asset: self, presetName: AVAssetExportPreset1280x720) else {
            completion(nil, nil)
            return
        }
        exporter.outputURL = outputURL
        exporter.outputFileType = .mp4
        // Pass Video Composition to the Exporter.
        exporter.videoComposition = videoComposition

        exporter.exportAsynchronously {
            DispatchQueue.main.async {
                completion(exporter.outputURL, nil)
            }
        }
    }

    static func instruction(_ assetTrack: AVAssetTrack, asset: AVAsset, time: CMTime, duration: CMTime, maxRenderSize: CGSize)
        -> (videoCompositionInstruction: AVMutableVideoCompositionInstruction, isPortrait: Bool) {
            let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: assetTrack)

            // Find out orientation from preffered transform.
            let assetInfo = orientationFromTransform(assetTrack.preferredTransform)

            // Calculate scale ratio according orientation.
            var scaleRatio = maxRenderSize.width / assetTrack.naturalSize.width
            if assetInfo.isPortrait {
                scaleRatio = maxRenderSize.height / assetTrack.naturalSize.height
            }

            // Set correct transform.
            var transform = CGAffineTransform(scaleX: scaleRatio, y: scaleRatio)
            transform = assetTrack.preferredTransform.concatenating(transform)
            layerInstruction.setTransform(transform, at: .zero)

            // Create Composition Instruction and pass Layer Instruction to it.
            let videoCompositionInstruction = AVMutableVideoCompositionInstruction()
            videoCompositionInstruction.timeRange = CMTimeRangeMake(start: time, duration: duration)
            videoCompositionInstruction.layerInstructions = [layerInstruction]

            return (videoCompositionInstruction, assetInfo.isPortrait)
    }

    static func orientationFromTransform(_ transform: CGAffineTransform) -> (orientation: UIImage.Orientation, isPortrait: Bool) {
        var assetOrientation = UIImage.Orientation.up
        var isPortrait = false

        switch [transform.a, transform.b, transform.c, transform.d] {
        case [0.0, 1.0, -1.0, 0.0]:
            assetOrientation = .right
            isPortrait = true

        case [0.0, -1.0, 1.0, 0.0]:
            assetOrientation = .left
            isPortrait = true

        case [1.0, 0.0, 0.0, 1.0]:
            assetOrientation = .up

        case [-1.0, 0.0, 0.0, -1.0]:
            assetOrientation = .down

        default:
            break
        }

        return (assetOrientation, isPortrait)
    }

}
