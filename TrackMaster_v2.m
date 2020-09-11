function TrackMaster()
addpath(genpath('E:\Video Tracking'));
serverName = 'localhost'; %the server we are going to connect with to get streaming data
vtXResolution = 720; %number of pixels of horizontal resolution for the video tracker
vtYResolution = 576; %number of pixels of vertical resolution for the video tracker
numberOfPasses = 150; %the number of times we will poll the server for new data before disconnecting and exiting the script
vt_acq_ent = 'VT1';

%% Figure for GUI
hFig = figure('Toolbar','none',...
    'NumberTitle','Off',...
    'color',[1 1 1],...
    'position',[59 200 700 420],... 
    'Name','TrackMaster v1');
%% Globals
% File handle for writing tracking data to
t_ = datestr(datetime('now'),'ddmmyyyy_HHMMSS');  

% File handle for writing Maze events data to
sLogFileObj          = ['MazeLog_' t_ '.txt'];

v.tracking_flag      = false;   % Enable position tracking
v.rewarding_flag     = false;   % Enable reward delivery
v.puffing_flag       = false;   % Enable air-puffing
v.rwd1_given         = false;
v.rwd2_given         = false;
v.puff_dir           = "";
v.puffed             = false;
v.armPuff            = false;   % Flag to indicate if the arduino has been told already to listen for a bream break

v.xValue             = [NaN];   %Moment by moment x posn
v.yValue             = [NaN];   %Moment by moment y posn
v.oldxvalue          = [NaN];   %TESTING ONLY
v.oldyvalue          = [NaN];   %TESTING ONLY
v.Posn               = [NaN,NaN]; %Animal's current position 
v.PosBuffer          = zeros(100,2);

v.no_runs            = 0;
%% Set up initial reward boundaries       
%Create initial boundary locations
v.InitialZones = {[10  200 105 200],...
                  [115 200 490 200],...
                  [605 200 105 200]};             
%% States & Zones

v.Zone1    = zeros(2,2);
v.Zone2    = zeros(2,2);
v.Zone3    = zeros(2,2);

v.zmat     = zeros(2,3); %Matrix for feeding location changes to

v.State1   = false; %In zone 1
v.State2   = false; %In zone 2(linear portion of track) having been in zone 1
v.State3   = false; %In zone 3
v.State4   = false; %In zone 2(linear portion of track) having been in zone 3
v.ZoneCurr = NaN; %Is a number from 1-3 reflecting a zone of this type
v.ZonePrev = NaN;
%% Setup serial object for reward collection
v.SerialName = '';
v.HWinfo = instrfind;
if ~isempty(v.HWinfo)
    fclose(v.HWinfo);
end
v.HWinfo = instrhwinfo('serial');

h_SerialObj = [];
%% GUI controls - Frame display 
% Prepare the plot handles
hFigAx=axes('Units','normalized',...
             'position',[0.02 0.2 0.6 0.75]);%VidSize(1) /VidSize(2)
set(hFigAx,'XTickLabel',[],'YTickLabel',[],'ticklength',[0 0]);
set(hFigAx,'box','on');
axis([0 vtXResolution 0 vtYResolution])
%% GUI controls - Acquisition

%Tracking Start Button
hStartButton = uicontrol(hFig,'Style', 'pushbutton', 'String', 'Start Tracking',...
    'Units','Normalized',...
    'Position', [0.05 0.1 0.15 0.05],...
    'Callback', @StartTracking);

%Tracking Stop Button
hStopButton = uicontrol(hFig,'Style', 'pushbutton', 'String', 'Stop Tracking',...
    'Units','Normalized',...
    'Position', [0.225 0.1 0.15 0.05],...
    'Callback', @StopTracking);

%% GUI controls - Serial

%Port Chooser Text
h_port_chooser_text = uicontrol('Style','text','fontweight', 'bold',...
    'Units','normalized',...
    'position',[0.65 0.65 0.3 .3],...
    'String','Choose a COM port:');

%Port Choose Dropdown
hPortDropdown= uicontrol('Style', 'popup',...
    'Units','normalized',...
    'Position', [0.7 0.8 0.2 .1],...
    'String', v.HWinfo.AvailableSerialPorts,...
    'Callback', @ChooseSerial);

%%%%% Connection Push  buttons:
% Connect button
h_start=uicontrol(hFig,'String', 'Connect',...
    'Units','normalized',...
    'position',[0.7 0.75 0.2 .05],... 
    'Enable', 'off',...
    'Callback',@SerialConnect);

% Disconnect button
h_stop=uicontrol(hFig,'String', 'Disconnect',...
    'Units','normalized',...
    'position',[0.7 0.7 0.2 .05],...
    'Enable', 'off',...
    'Callback',@SerialDisconnect);
%% GUI controls - Task Control

%%%%% Connection Push  buttons:
h_ControlText = uicontrol('Style','text','fontweight', 'bold',...
    'Units','normalized',...
    'position',[0.65 0.35 0.3 .25],...
    'String','Task Controls');

%Reward Delivery text
h_ControlText = uicontrol('Style','text',...
    'Units','normalized',...
    'position',[0.65 0.5 0.3 .06],...
    'String','Reward Delivery');

%Reward Delivery Push Button
hRwdDeliveryOn = uicontrol('Style', 'pushbutton', 'String', 'Rwd On',...
    'Units','Normalized',...
    'Position', [0.7 0.475 0.1 0.05],...
    'Enable', 'off',...
    'Callback', @RewardDeliveryOn);
hRwdDeliveryOff = uicontrol('Style', 'pushbutton', 'String', 'Rwd Off',...
    'Units','Normalized',...
    'Position', [0.8 0.475 0.1 0.05],...
    'Enable', 'off',...
    'Callback', @RewardDeliveryOff);

%AirPuff text
h_ControlText = uicontrol('Style','text',...
    'Units','normalized',...
    'position',[0.65 0.4 0.3 .06],...
    'String','Air Puff!');

%Air Puff Push Button
hPuffDeliveryOn = uicontrol(hFig,'Style', 'pushbutton', 'String', 'Air Puff On',...
    'Units','Normalized',...
    'Position', [0.7 0.375 0.1 0.05],...
    'Enable', 'off',...
    'Callback', @ValveControlOn);
hPuffDeliveryOff = uicontrol(hFig,'Style', 'pushbutton', 'String', 'Air Puff Off',...
    'Units','Normalized',...
    'Position', [0.8 0.375 0.1 0.05],...
    'Enable', 'off',...
    'Callback', @ValveControlOff);

%Air Puff Direction
h_ControlText = uicontrol('Style','text','fontweight', 'bold',...
    'Units','normalized',...
    'position',[0.4 0.05 0.22 .125],...
    'String','Puff Direction');

%Puff Direction Push Buttons
hPuffFwd = uicontrol('Style', 'pushbutton', 'String', 'Forward',...
    'Units','Normalized',...
    'Position', [0.42 0.075 0.08 0.05],...
    'Enable', 'on',...
    'Callback', @PuffFwd); %Forward indicates heading from left to right (ie - while in state 2)
hPuffBackward = uicontrol('Style', 'pushbutton', 'String', 'Backward',...
    'Units','Normalized',...
    'Position', [0.52 0.075 0.08 0.05],...
    'Enable', 'on',...
    'Callback', @PuffBackward); %Backward indicates right to left (ie - while in state 4)
%% GUI Controls - Manual Control

%Manual Control text
h_ControlText = uicontrol('Style','text','fontweight', 'bold',...
    'Units','normalized',...
    'position',[0.65 0.05 0.3 .25],...
    'String','Manual Control');

%Reward Delivery text
h_ControlText = uicontrol('Style','text',...
    'Units','normalized',...
    'position',[0.65 0.2 0.3 .06],...
    'String','Lick Ports');

%Triplick Buttons
h_Lick1 = uicontrol(hFig,'Style', 'pushbutton', 'String', 'Lickport 1',...
    'Units','Normalized',...
    'Position', [0.7 0.175 0.1 0.05],...
    'Enable', 'off',...
    'Callback', @Triplick1);

h_Lick2 = uicontrol(hFig,'Style', 'pushbutton', 'String', 'Lickport 2',...
    'Units','Normalized',...
    'Position', [0.8 0.175 0.1 0.05],...
    'Enable', 'off',...
    'Callback', @Triplick2);

%AirPuff text
h_ControlText = uicontrol('Style','text',...
    'Units','normalized',...
    'position',[0.65 0.1 0.3 .06],...
    'String','Air Puff!');

%Air Puff Push Button
h_Puff = uicontrol(hFig,'Style', 'pushbutton', 'String', 'Air Puff!!',...
    'Units','Normalized',...
    'Position', [0.7 0.075 0.2 0.05],...
    'Enable', 'off',...
    'Callback', @Puff);
%% Plot reward zones and buffer
for k = 1:length(v.InitialZones)           
    hZones{k} = imrect(gca,v.InitialZones{k});            
    eval(sprintf('addNewPositionCallback(hZones{%d},@(p)assignin(''base'',''Bound%d'',p));', k,k))            
end

if exist('Bound1') == 0
    Bound1 = getPosition(hZones{1});
end
if exist('Bound2') == 0
    Bound2 = getPosition(hZones{2});
end
if exist('Bound3') == 0
    Bound3 = getPosition(hZones{3});
end
%% Nested Functions
    function StartTracking(hObject, eventdata, handles)
        disp('Starting tracking')
        
        if NlxAreWeConnected() ~= 1
            succeeded = NlxConnectToServer(serverName);
          
            if succeeded ~= 1
                fprintf('FAILED connect to %s. Exiting script.\r', serverName);
                return;
            else
                fprintf('Connected to %s.\r', serverName);
            end
        end
        
        %Identify this program to the server.
        NlxSetApplicationName('MATLAB Position Tracking');
        
      
        [~, cheetahObjects, ~] = NlxGetDASObjectsAndTypes(); %NlxGetCheetahObjectsAndTypes
        if isempty(strmatch(vt_acq_ent, cheetahObjects))
            fprintf('FAILED the acquisition entity %s does not exist.\r', vt_acq_ent);
            %You should always disconnect from a server before terminating your script.
            NlxDisconnectFromServer();
            return;
        end
        
        %% Open the data stream for the VT acquisition entity.
        %This tells Cheetah to begin streaming data for the VT acq ent.
        NlxOpenStream(vt_acq_ent);
        
        %%
        [~, timeStampArray, ~, ~, ~, ~] = NlxGetNewVTData(vt_acq_ent);
        cheetah_start_time = max(timeStampArray);
        %record time trials started
        v.starttime = clock();
        v.currenttime = clock();
        timetaken = 0;
        v.loopcounter = 0;
        v.tracking_flag = true;
        
        TrackPosition()
                
    end
    function StopTracking(hObject, eventdata, handles)
        disp('Stopping tracking')
        ISrunning = false;
        
        %Close the stream for the VT acq ent. This stops streaming of VT data without
        %disconnecting from the server
        NlxCloseStream(vt_acq_ent);
        %Disconnect from the server.
        NlxDisconnectFromServer();
        fprintf('Disconnected from %s.\r', serverName);
       
    end
    function ChooseSerial(hObject, eventdata, handles)
        v.SerialName = hObject.String{hObject.Value};
        disp(['Choosing Serial port: ' v.SerialName])
        set(h_start,'Enable','on')
    end
    function SerialConnect(hObject, eventdata, handles)
        set(h_port_chooser_text,'string', ['Connecting to: ' , v.SerialName ]);
        h_SerialObj = serial(v.SerialName,'BaudRate',500000);

        fopen(h_SerialObj)
        
        hLogFileObj = fopen(sLogFileObj,'a');
        
        set(h_port_chooser_text,'string',['Connected to: ' , v.SerialName ]);
        set(hPortDropdown,'Enable','off')
        set(h_start,'Enable','off')
        set(h_stop,'Enable','on')
        set(hRwdDeliveryOn,'Enable','on')
        set(hPuffDeliveryOn,'Enable','on')
        set(h_Lick1,'Enable','on')
        set(h_Lick2,'Enable','on')
        set(h_Puff,'Enable','on')
    end
    function SerialDisconnect(hObject, eventdata, handles)
        
        fclose(h_SerialObj)
        delete(h_SerialObj)
        
        fclose(hLogFileObj);
        set(h_port_chooser_text,'string', 'Choose a COM port:');
        set(hPortDropdown,'Enable','on')
        set(h_start,'Enable','off')
        set(h_stop,'Enable','off')
        set(hRwdDeliveryOn,'Enable','off')
        set(hRwdDeliveryOff,'Enable','off')
        set(hPuffDeliveryOn,'Enable','off')
        set(hPuffDeliveryOff,'Enable','off')
        set(h_Lick1,'Enable','off')
        set(h_Lick2,'Enable','off')
        set(h_Puff,'Enable','off')
    end
    function TrackPosition()
       
        firstloop = 0;
        while v.tracking_flag == true
            v.loopcounter = v.loopcounter+1;

            %% Location Finder
            
            %Pause to let some new data load up in NetCom's buffers.
%             pause(0.1);
            
            %Request all new VT data that has been acquired since the last pass.
            [~, ~, locationArray, ~, VTRecsReturned, ~] = NlxGetNewVTData(vt_acq_ent);
            %Loop through all of the retrieved data.
            for vtRecordNumber = 1:VTRecsReturned
                %Get the X and Y location value for this VT frame. The
                %locationArray is in the form [x1, y1, x2, y2, ... xN, yN].
                x1 = locationArray(2 * vtRecordNumber - 1);
                y1 = locationArray(2 * vtRecordNumber);
                if x1 > 0 && y1 > 0
                    v.xValue = [v.xValue, x1];
                    v.yValue = [v.yValue, y1];
                    
                end
            end

            xMode = mean(single(v.xValue));
            yMode = mean(single(v.yValue));
            v.Posn = [xMode, yMode];
           
            hold on
            if rem(v.loopcounter,1)==0
                plot(v.xValue, v.yValue, 'bo');%TESTING ONLY
                plot(xMode, yMode, 'r.');%TESTING ONLY
                drawnow
            end
          
            %% State Determination
            
            %Creates a vector of boundary co-ordinates
            for m = 1:length(v.InitialZones)
                %eval(sprintf('Zone%d = zeros(2,2);',m))
                eval(sprintf(['v.Zone%d(1,:) = [Bound%d(1),Bound%d(1) + '...
                    'Bound%d(3)];'], m,m,m,m)); 
                eval(sprintf(['v.Zone%d(2,:) = [Bound%d(2),Bound%d(2) + '...
                    'Bound%d(4)];'], m,m,m,m));
            end
            
            %Updates row 1 of the zmat array based on boundary position
            for iZ = 1:length(v.InitialZones)
                eval(sprintf(['v.zmat(1,iZ) = inpolygon(v.Posn(1), v.Posn(2),'...
                    'v.Zone%d(1,:), v.Zone%d(2,:));'], iZ, iZ));
            end
                        
            %Establishes current zone and previous zone (if row 1 and 2 of
            %zmat are different)
            if isempty(find(v.zmat(1,:)))
                continue
            else
                v.ZoneCurr = find(v.zmat(1,:));
                %Sets previous zone as current zone on first iteration of loop
                if firstloop < 1
                    v.ZonePrev = v.ZoneCurr;
                    firstloop = firstloop + 1;
                else
                    if isequal(v.zmat(1,:),v.zmat(2,:)) == 0
                        v.ZonePrev = find(v.zmat(2,:));
                    end
                end
                
                %Updates row 2 of the zmat array based on boundary position
                for iZ = 1:length(v.InitialZones)
                    eval(sprintf(['v.zmat(2,iZ) = inpolygon(v.Posn(1),'...
                            'v.Posn(2), v.Zone%d(1,:), v.Zone%d(2,:));'], iZ, iZ));
                end
                
            end
            
            %State based on current and previous zones
            if v.ZoneCurr == 2 & v.ZonePrev == 1
                v.State1 = false;
                v.State2 = true;
                v.State3 = false;
                v.State4 = false;
            elseif v.ZoneCurr == 3 & v.ZonePrev == 2
                v.State1 = false;
                v.State2 = false;
                v.State3 = true;
                v.State4 = false;
            elseif v.ZoneCurr == 2 & v.ZonePrev == 3
                v.State1 = false;
                v.State2 = false;
                v.State3 = false;
                v.State4 = true;
            elseif v.ZoneCurr == 1 & v.ZonePrev == 2
                v.State1 = true;
                v.State2 = false;
                v.State3 = false;
                v.State4 = false;
            else
                v.State1 = false;
                v.State2 = false;
                v.State3 = false;
                v.State4 = false;
            end
            
            %% Reward Stuff
            
            if v.rewarding_flag == true
                if v.State1 == true
                    v.rwd1_given = false;
                elseif v.State3 == true
                    v.rwd2_given = false;
                elseif v.State2 == true
                    while v.rwd2_given == false
                        fprintf(h_SerialObj, '%s\n','4');
                        LogStr = [datestr(datetime('now')) ': Lick port 2 Triggered'];
                        v.rwd2_given = true;
                        disp(LogStr)
                        fprintf(hLogFileObj,'%s\n',LogStr);
                    end
                elseif v.State4 == true
                    while v.rwd1_given == false
                        fprintf(h_SerialObj, '%s\n','1');
                        LogStr = [datestr(datetime('now')) ': Lick port 1 Triggered'];
                        v.rwd1_given = true;
                        disp(LogStr)
                        fprintf(hLogFileObj, '%s\n',LogStr);
                    end
                end
            end
            
            %% Aversion Stuff
            
            %Turns on the air-puff in zone 2 and the relevant state
            %depending on whether forward or backward buttons are selected
            
            % - If the animal turns round and returns to the previous reward
            %point, the air puff will turn on again

            if v.puffing_flag == true
                
                if v.State1 == true  && strcmp(v.puff_dir, "Forward")
                    if v.puffed == false
                        if v.armPuff == false
                            fprintf(h_SerialObj, '%s\n', '5');
                            v.armPuff = true;
                            disp('Arming Arduino: Forward condition')
                        end
                    end
                elseif v.State2 == true
                    if v.puffed == false && strcmp(v.puff_dir, "Forward")
                       if v.armPuff == true
                           if h_SerialObj.BytesAvailable >0
                               Broken = fscanf(h_SerialObj);
                               if strcmp(Broken(1), 'B')
                                   LogStr = [datestr(datetime('now')) ': Air Puff Delivered (Forward)'];
                                   fprintf(hLogFileObj, '%s\n',LogStr);
                                   disp(LogStr)
                                   v.puffed = true;
                                   v.armPuff = false;
                                   disp('Arduino beam break monitoring has been disarmed')
                               end
                           else
                              %disp(['Waiting for beam break... ' num2str(h_SerialObj.BytesAvailable)])
                           end
                       end
                    end
                elseif v.State3 == true && strcmp(v.puff_dir, "Forward")
                    v.puffed = false;
                elseif v.State3 == true && strcmp(v.puff_dir, "Backward")
                    if v.puffed == false
                        if v.armPuff == false
                            fprintf(h_SerialObj, '%s\n', '5');
                            v.armPuff = true;
                            disp('Arming Arduino: Backward condition')
                        end
                    end
                elseif v.State4 == true
                    if v.puffed == false && strcmp(v.puff_dir, "Backward")
                       if v.armPuff == true
                           if h_SerialObj.BytesAvailable >0
                               Broken = fscanf(h_SerialObj);
                               if strcmp(Broken(1), 'B')
                                   LogStr = [datestr(datetime('now')) ': Air Puff Delivered (Forward)'];
                                   fprintf(hLogFileObj, '%s\n',LogStr);
                                   disp(LogStr)
                                   v.puffed = true;
                                   v.armPuff = false;
                                   disp('Arduino beam break monitoring has been disarmed')
                               end
                           else
                              %disp(['Waiting for beam break... ' num2str(h_SerialObj.BytesAvailable)])
                           end
                       end
                    end
                elseif v.State1 == true && strcmp(v.puff_dir, "Backward")
                    v.puffed = false;
                end
            end

            %% Reset location values
                                    
%             v.oldxvalue = [v.oldxvalue, v.xValue];%TESTING ONLY
%             v.oldyvalue = [v.oldyvalue, v.yValue];%TESTING ONLY
            v.xValue = [];
            v.yValue = [];
            
            yMode = [];
            xMode = [];
            v.Posn = [NaN,NaN];
            
            %% Set clock for current loop
            v.currenttime = clock();
            timetaken = etime(v.currenttime, v.starttime);
            title(['time gone (s): ',num2str(timetaken)])
                        
        end
    end
    function RewardDeliveryOn(hObject, eventdata, handles)
        
        set(hRwdDeliveryOff,'Enable','on')
        disp('Working');
        v.rewarding_flag = true;
        set(hRwdDeliveryOn, 'Enable','off')
                        
    end
    function RewardDeliveryOff(hObject, eventdata, handles)
        
        set(hRwdDeliveryOn,'Enable','on')
        v.rewarding_flag = false;
        set(hRwdDeliveryOff,'Enable','off')
        
    end    
    function ValveControlOn(hObject, eventdata, handles)
        
        %See 'Monitornosepokes' function (line 154) in BlackJack.ino code    
        set(hPuffDeliveryOff,'Enable','on')
        v.puffing_flag = true;
        set(hPuffDeliveryOn,'Enable','off')
        
    end
    function ValveControlOff(hObject, eventdata, handles)
        
        set(hPuffDeliveryOn,'Enable','on')
        v.puffing_flag = false;
        set(hPuffDeliveryOff,'Enable','off')
        
    end
    function Triplick1(hObject, eventdata, handles)
        fprintf(h_SerialObj,'%s\n','1');
        LogStr = [datestr(datetime('now')) ': Lick port 1 Triggered'];
        disp(LogStr)
        fprintf(hLogFileObj,'%s\n',LogStr);
    end
    function Triplick2(hObject, eventdata, handles)
        fprintf(h_SerialObj, '%s\n', '4');
        LogStr = [datestr(datetime('now')) ': Lick port 2 Triggered'];
        disp(LogStr)
        fprintf(hLogFileObj,'%s\n',LogStr);
    end
    function Puff(hObject, eventdata, handles)
        fprintf(h_SerialObj,'%s\n','6'); %Possibly change based on arduino code
        LogStr = [datestr(datetime('now')) ': Air Puff Delivered'];
        disp(LogStr)
        fprintf(hLogFileObj,'%s\n',LogStr);
    end
    function PuffFwd(hObject, eventdata, handles)
        
        set(hPuffFwd,'Enable','off')
        set(hPuffBackward,'Enable','on')
        v.puff_dir = "Forward";
        disp(v.puff_dir)
        
    end
    function PuffBackward(hObject, eventdata, handles)
        
        set(hPuffBackward,'Enable','off')
        set(hPuffFwd,'Enable','on')
        v.puff_dir = "Backward";
        %disp(v.PuffDir)
        
    end
end