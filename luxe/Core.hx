package luxe;

import snow.Snow;
import snow.types.Types;
import snow.utils.ByteArray;
import snow.window.Window;

import Luxe;
import luxe.IO;
import luxe.Audio;
import luxe.Events;
import luxe.Emitter;
import luxe.Input;
import luxe.Scene;
import luxe.Debug;
import luxe.Timer;
import luxe.Physics;
import luxe.AppConfig;
import luxe.resource.ResourceManager;

import luxe.debug.ProfilerDebugView;

import phoenix.Renderer;
import phoenix.Texture;
import phoenix.Shader;

import luxe.Game;
import luxe.Log._verbose;
import luxe.Log._debug;
import luxe.Log.log;


@:noCompletion
@:keep
@:log_as('luxe')
class Core extends snow.App {

        //the game object running the core
    public var game : Game;
    public var appconfig : AppConfig;

        //if the console is displayed atm
    public var console_visible : Bool = false;
        /** Set to true if the app is running without a window */
    public var headless : Bool = false;


//Sub Systems, mostly in order of importance
    public var emitter   : Emitter;
    public var debug     : Debug;
    public var io        : IO;
    public var draw      : Draw;
    public var timer     : Timer;
    public var events    : Events;
    public var input     : Input;
    public var audio     : Audio;
    public var scene     : Scene;
    public var resources : ResourceManager;
    public var renderer  : Renderer;
    public var screen    : luxe.Screen;
    public var physics   : Physics;

//flags

       //if we have started a shutdown
    public var shutting_down : Bool = false;
    public var has_shutdown : Bool = false;
    public var inited : Bool = false;

    @:noCompletion public function new( _game:Game, _config:AppConfig ) {

        super();

        appconfig = _config;
        game = _game;

            //Store the core for reference in the game
        game.app = this;

            //Create internal stuff
        emitter = new Emitter();

            //Set external references
        Luxe.core = this;
        Luxe.utils = new luxe.utils.Utils(this);

    } //new


        //This gets called once snow has booted us - this is
    override function ready() {

        Luxe.version = haxe.Resource.getString('version');
            //Don't change this, it matches semantic versioning http://semver.org/
        Luxe.build = Luxe.version + haxe.Resource.getString('build');

        log('version ${Luxe.build}');

            //Create the subsystems
        init();

            //
        _debug('ready.');

            //Call the main ready function
            //and send the ready event to the game
        game.ready();

            //shutdown can come from the ready function
        if(!shutting_down) {

                //emit the init event
                //so that scene and others can start up
            emitter.emit('init');
            inited = true;

                //Reset the physics (starts the timer etc)
            physics.reset();

                //Now, if no main loop is requested we should immediately shutdown
            if(!app.snow_config.has_loop) {
                shutdown();
            }

        } //!shutting down

    } //ready

    override function ondestroy() {

            //Make sure all systems know we are going down
        shutting_down = true;

        log('shutting down...');

            //shutdown the game class
        game.ondestroy();

            //shutdown the default scene
        emitter.emit('destroy');

            //Order is imporant here too
        if(renderer != null) {
            renderer.destroy();
        }

        physics.destroy();
        input.destroy();
        audio.destroy();
        timer.destroy();
        events.destroy();
        debug.destroy();

            //Clear up for GC
        emitter = null;
        input = null;
        audio = null;
        events = null;
        timer = null;
        debug = null;
        Luxe.utils = null;

            //Flag it
        has_shutdown = true;

        log('goodbye.');

    }

    public function init() {

            //Create the subsystems
        _debug('creating subsystems...');

            //Order is important here

        Luxe.debug = debug = new Debug( this );
        Luxe.io = io = new IO( this );

        draw = new Draw( this );
        timer = new Timer( this );
        events = new Events();
        audio = new Audio( this );
        input = new Input( this );
        physics = new Physics( this );

            //should be up earlier
        resources = new ResourceManager();
        Luxe.resources = resources;

            //flag for later
        headless = (app.window == null);

        if(!headless) {
                //listen for window events
            app.window.onevent = window_event;
                //create the renderer
            renderer = new Renderer( this );
                //assign the globals
            Luxe.renderer = renderer;
        }

            //if there is a window,
            //store the size
        var _window_w = 0;
        var _window_h = 0;

        if(app.window != null) {
            _window_w = app.window.width;
            _window_h = app.window.height;
        }

            //store the size for access from API
        screen = new luxe.Screen( this, _window_w, _window_h );

            //Now make sure
            //they start up

        debug.init();
        io.init();
        timer.init();
        audio.init();
        input.init();

        if(!headless) {
            renderer.init();
        }

        physics.init();

        Luxe.audio = audio;
        Luxe.draw = draw;
        Luxe.events = events;
        Luxe.timer = timer;
        Luxe.input = input;

        if(!headless) {
            Luxe.camera = new luxe.Camera({ name:'default camera', view:renderer.camera });
        }

        Luxe.physics = physics;

        scene = new Scene('default scene');
        Luxe.scene = scene;

        if(!headless) {
            scene.add(Luxe.camera);
            debug.create_debug_console();
        }

            //and even more finally, tell snow we want to
            //know when it's rendering the window so we can draw
        if(app.window != null && !headless) {

            app.window.onrender = render;

                //start here because end is called first below
            debug.start(core_tag_update, 50);
            debug.start(core_tag_renderdt, 50);

        } //app.window != null && !headless

    } //init

    public function shutdown() {

            //Make sure all systems know we are going down
        shutting_down = true;

            //shutdown snow, which calls ondestroy for us
        snow.Snow.next(app.shutdown);

    } //shutdown

    public function on<T>(event:String, handler:T->Void ) {
        emitter.on(event, handler);
    }

    public function off<T>(event:String, handler:T->Void ) {
        return emitter.off(event, handler);
    }

    public function emit<T>(event:String, ?data:T) {
        return emitter.emit(event, data);
    }

        //called by snow
    override function onevent( event:snow.types.Types.SystemEvent ) {

            //forward to game class
        game.onevent( event );

    } //onevent

        //called by snow
    override function update( dt:Float ) {

        #if luxe_fullprofile
            _verbose('on_update ' + Luxe.time);
        #end //luxe_fullprofile

        if(has_shutdown) return;

        debug.end(core_tag_update);
        debug.start(core_tag_update);

            //Update all the subsystems, again, order important
//Timers first
            #if luxe_fullprofile debug.start(core_tag_timer); #end
        timer.process();
            #if luxe_fullprofile debug.end(core_tag_timer); #end
//Input second
            #if luxe_fullprofile debug.start(core_tag_input); #end
        input.process();
            #if luxe_fullprofile debug.end(core_tag_input); #end
//Audio
            #if luxe_fullprofile debug.start(core_tag_audio); #end
        audio.process();
            #if luxe_fullprofile debug.end(core_tag_audio); #end
//Events
            #if luxe_fullprofile debug.start(core_tag_events); #end
        events.process();
            #if luxe_fullprofile debug.end(core_tag_events); #end
//Physics
            //note that this does not update the physics, simply processes the active engines
        physics.process();

//Run update callbacks
            debug.start(core_tag_updates);
        emitter.emit('update', dt);
            debug.end(core_tag_updates);

//Update the game class for the game
            debug.start( game_tag_update );
        game.update(dt);
            debug.end( game_tag_update );

//And finally the debug stuff
            #if luxe_fullprofile debug.start(core_tag_debug); #end
        debug.process();
            #if luxe_fullprofile debug.end(core_tag_debug); #end

    } //update

    function window_event( _event:snow.types.Types.WindowEvent ) {

        if(shutting_down) {
            return;
        }

        emitter.emit('window.event', _event );

        switch(_event.type) {

            case WindowEventType.moved : {
                emitter.emit('window.moved', _event );
            } //moved

            case WindowEventType.resized : {
                screen.internal_resized(_event.event.x, _event.event.y);
                renderer.internal_resized(_event.event.x, _event.event.y);
                emitter.emit('window.resized', _event );
            } //resized

            case WindowEventType.size_changed : {
                screen.internal_resized(_event.event.x, _event.event.y);
                renderer.internal_resized(_event.event.x, _event.event.y);
                emitter.emit('window.size_changed', _event );
            } //size_changed

            case WindowEventType.minimized : {
                emitter.emit('window.minimized', _event );
            } //minimized

            case WindowEventType.restored : {
                emitter.emit('window.restored', _event );
            } //restored

            default: {}

        } //switch

    } //window_event

    function render( window:Window ) {

        if(shutting_down) {
            return;
        }

        debug.end(core_tag_renderdt);
        debug.start(core_tag_renderdt);

        if(!headless) {

            debug.start(core_tag_render);

            emitter.emit('prerender');
            game.onprerender();

                emitter.emit('render');
                game.onrender();
                renderer.process();

            emitter.emit('postrender');
            game.onpostrender();

            debug.end(core_tag_render);

        } //!headless

    } //render

    public function show_console(_show:Bool = true) {

        console_visible = _show;
        debug.show_console(console_visible);

    } //show_console

//input events
//keys
    override function onkeydown( keycode:Int, scancode:Int, repeat:Bool, mod:ModState, timestamp:Float, window_id:Int ) {

        var event : KeyEvent = {
            scancode : scancode,
            keycode : keycode,
            state : InteractState.down,
            mod : mod,
            repeat : repeat,
            timestamp : timestamp,
            window_id : window_id
        }

        if(!shutting_down) {

                //check for named input
            input.check_named_keys(event, true);
            emitter.emit('keydown', event);

            game.onkeydown(event);

            if(scancode == Scan.grave) {
                show_console( !console_visible );
            }

        } //!shutting down

    } //onkeydown

    override function onkeyup( keycode:Int, scancode:Int, repeat:Bool, mod:ModState, timestamp:Float, window_id:Int ) {

        var event : KeyEvent = {
            scancode : scancode,
            keycode : keycode,
            state : InteractState.up,
            mod : mod,
            repeat : repeat,
            timestamp : timestamp,
            window_id : window_id
        }

        if(!shutting_down) {

                //check for named input
            input.check_named_keys(event);
            emitter.emit('keyup', event);

            game.onkeyup(event);

        } //!shutting down

    } //onkeyup

    override function ontextinput( text:String, start:Int, length:Int, type:snow.types.TextEventType, timestamp:Float, window_id:Int ) {

        var _type : TextEventType = TextEventType.unknown;

        switch(type) {
            case edit: _type = TextEventType.edit;
            case input: _type = TextEventType.input;
            default: {
                return;
            }
        }

        var event : TextEvent = {
            text : text,
            start : start,
            length : length,
            type : _type,
            timestamp : timestamp,
            window_id : window_id
        }

        if(!shutting_down) {

            emitter.emit('textinput', event);

            game.ontextinput(event);

        } //!shutting_down

    } //ontextinput

//input

    public function oninputdown( name:String, event:InputEvent ) {

        if(!shutting_down) {

            emitter.emit('inputdown', { name:name, event:event });

            game.oninputdown( name, event );

        } //!shutting_down

    } //oninputdown

    public function oninputup( name:String, event:InputEvent ) {

        if(!shutting_down) {

            emitter.emit('inputup', { name:name, event:event });

            game.oninputup( name, event );

        } //!shutting_down

    } //oninputup

//mouse

    override function onmousedown( x:Int, y:Int, button:Int, timestamp:Float, window_id:Int ) {

            //this has to be a new value because if it's cached it sends in references that get kept by user code
        screen.cursor.set_internal(new luxe.Vector( x, y ));

        var event : MouseEvent = {
            timestamp : timestamp,
            window_id : window_id,
            state : InteractState.down,
            button : button,
            x : x,
            y : y,
            xrel : x,
            yrel : y,
            pos : screen.cursor.pos,
        }

        if(!shutting_down) {

            input.check_named_mouse(event, true);
            emitter.emit('mousedown', event);
            game.onmousedown(event);

        } //!shutting_down

    } //onmousedown

    override function onmouseup( x:Int, y:Int, button:Int, timestamp:Float, window_id:Int ) {

            //see notes on new in mousedown
        screen.cursor.set_internal(new luxe.Vector( x, y ));

        var event : MouseEvent = {
            timestamp : timestamp,
            window_id : window_id,
            state : InteractState.up,
            button : button,
            x : x,
            y : y,
            xrel : x,
            yrel : y,
            pos : screen.cursor.pos
        }

        if(!shutting_down) {

            input.check_named_mouse(event);
            emitter.emit('mouseup', event);
            game.onmouseup(event);

        } //!shutting_down

    } //onmouseup

    override function onmousemove( x:Int, y:Int, xrel:Int, yrel:Int, timestamp:Float, window_id:Int ) {

            //see notes on new in mousedown
        screen.cursor.set_internal(new luxe.Vector( x, y ));

        var event : MouseEvent = {
            timestamp : timestamp,
            window_id : window_id,
            state : InteractState.move,
            button : MouseButton.none,
            x : x,
            y : y,
            xrel : xrel,
            yrel : yrel,
            pos : screen.cursor.pos
        }

        if(!shutting_down) {

            emitter.emit('mousemove', event);
            game.onmousemove(event);

        } //!shutting_down

    } //onmousemove

    override function onmousewheel( x:Int, y:Int, timestamp:Float, window_id:Int ) {

        var event : MouseEvent = {
            timestamp : timestamp,
            window_id : window_id,
            state : InteractState.wheel,
            button : MouseButton.none,
            x : x,
            y : y,
            xrel : x,
            yrel : y,
            pos : screen.cursor.pos
        }

        if(!shutting_down) {

            input.check_named_mouse(event, false);
            emitter.emit('mousewheel', event);
            game.onmousewheel(event);

        } //!shutting_down

    } //onmousewheel

//touch
        //cached touch pos
    var _touch_pos : Vector;

    override function ontouchdown( x:Float, y:Float, touch_id:Int, timestamp:Float ) {

         _touch_pos = new luxe.Vector( x, y );

        var event : TouchEvent = {
            state : InteractState.down,
            timestamp : timestamp,
            touch_id : touch_id,
            x : x,
            y : y,
            dx : x,
            dy : y,
            pos : _touch_pos
        }

        if(!shutting_down) {

            emitter.emit('touchdown', event);

            game.ontouchdown(event);

            #if !no_debug_console

                    //3 finger tap when console opens will switch tabs
                if(app.input.touch_count == 3) {
                    if(console_visible) {
                        debug.switch_view();
                    }
                }

                    //4 finger tap toggles console
                if(app.input.touch_count == 4) {
                    show_console( !console_visible );
                }

            #end //no_debug_console

        } //!shutting_down

    } //ontouchdown

    override function ontouchup( x:Float, y:Float, touch_id:Int, timestamp:Float ) {

         _touch_pos = new luxe.Vector( x, y );

        var event : TouchEvent = {
            state : InteractState.up,
            timestamp : timestamp,
            touch_id : touch_id,
            x : x,
            y : y,
            dx : x,
            dy : y,
            pos : _touch_pos
        }

        if(!shutting_down) {

            emitter.emit('touchup', event);
            game.ontouchup(event);

        } //!shutting_down

    } //ontouchup

    override function ontouchmove( x:Float, y:Float, dx:Float, dy:Float, touch_id:Int, timestamp:Float ) {

        _touch_pos = new luxe.Vector( x, y );

        var event : TouchEvent = {
            state : InteractState.move,
            timestamp : timestamp,
            touch_id : touch_id,
            x : x,
            y : y,
            dx : dx,
            dy : dy,
            pos : _touch_pos
        }

        if(!shutting_down) {

            emitter.emit('touchmove', event);
            game.ontouchmove(event);

        } //!shutting_down

    } //ontouchmove

//gamepad

    override function ongamepadaxis( gamepad:Int, axis:Int, value:Float, timestamp:Float ) {

        var event : GamepadEvent = {
            timestamp : timestamp,
            type : GamepadEventType.axis,
            state : InteractState.axis,
            gamepad : gamepad,
            button : -1,
            axis : axis,
            value : value
        }

        if(!shutting_down) {

            emitter.emit('gamepadaxis',event);
            game.ongamepadaxis(event);

        } //!shutting_down

    } //ongamepadaxis

    override function ongamepaddown( gamepad:Int, button:Int, value:Float, timestamp:Float ) {

        var event : GamepadEvent = {
            timestamp : timestamp,
            type : GamepadEventType.button,
            state : InteractState.down,
            gamepad : gamepad,
            button : button,
            axis : -1,
            value : value
        }

        if(!shutting_down) {

            emitter.emit('gamepaddown',event);
            game.ongamepaddown(event);

        } //!shutting_down

    } //ongamepadbuttondown

    override function ongamepadup( gamepad:Int, button:Int, value:Float, timestamp:Float ) {

        var event : GamepadEvent = {
            timestamp : timestamp,
            type : GamepadEventType.button,
            state : InteractState.up,
            gamepad : gamepad,
            button : button,
            axis : -1,
            value : value
        }

        if(!shutting_down) {

            emitter.emit('gamepadup', event);
            game.ongamepadup(event);

        } //!shutting_down

    } //ongamepadup

    override function ongamepaddevice( gamepad:Int, type:GamepadDeviceEventType, timestamp:Float ) {

        var _event_type : GamepadEventType = GamepadEventType.unknown;

        switch(type) {
            case GamepadDeviceEventType.device_added:
                _event_type = GamepadEventType.device_added;
            case GamepadDeviceEventType.device_removed:
                _event_type = GamepadEventType.device_removed;
            case GamepadDeviceEventType.device_remapped:
                _event_type = GamepadEventType.device_remapped;
            default:
        }

        var event : GamepadEvent = {
            timestamp : timestamp,
            type : _event_type,
            state : InteractState.none,
            gamepad : gamepad,
            button : -1,
            axis : -1,
            value : 0
        }

        if(!shutting_down) {

            game.ongamepaddevice(event);

        } //!shutting_down

    } //ongamepaddevice

        /** return what the game decides for runtime config */
    override function config( config:AppConfig ) : AppConfig {

            config.window.width = appconfig.window.width;
            config.window.height = appconfig.window.height;
            config.window.fullscreen = appconfig.window.fullscreen;
            config.window.borderless = appconfig.window.borderless;
            config.window.resizable = appconfig.window.resizable;
            config.window.title = appconfig.window.title;

       return game.config( config );

    } //config

//Noisy stuff

    static var core_tag_update : String = 'real dt';
    static var core_tag_renderdt : String = 'render dt';
    static var game_tag_update : String = 'game.update';
    static var core_tag_render : String = 'core.render';
    static var core_tag_debug : String = 'core.debug';
    static var core_tag_updates : String = 'core.updates';
    static var core_tag_events : String = 'core.events';
    static var core_tag_audio : String = 'core.audio';
    static var core_tag_input : String = 'core.input';
    static var core_tag_timer : String = 'core.timer';
    static var core_tag_scene : String = 'core.scene';


} //Core
