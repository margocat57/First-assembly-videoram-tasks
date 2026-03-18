#define MINIAUDIO_IMPLEMENTATION  
#include "miniaudio.h"
#include <gtk/gtk.h>
// g++ CRACK/CR_PROG/ADDIT/PATCH.CPP -o test $(pkg-config --cflags --libs gtk+-3.0) -I/mnt/c/Users/Margarita -std=c++11 -lpthread -ldl -lpulse


const int SUM = 9944;
const int WINDOW_WIDTH = 900;
const int WINDOW_HEIGHT = 600;

const int CRACK_BUTTON_WIDTH = 200;
const int CRACK_BUTTON_HEIGHT = 80;

const int FILE_BUTTON_WIDTH = 350;
const int FILE_BUTTON_HEIGHT = 80;

const int CRACK_BUTTON_X = 550; 
const int CRACK_BUTTON_Y = 220;

const int FILE_BUTTON_X = 500;
const int FILE_BUTTON_Y = 150;

struct AudioData {
    ma_engine engine;
    ma_sound sound_wait;  
    ma_sound sound_success;  
    ma_sound sound_fail;  

    bool success_init;
    bool fail_init;
};

struct Widgets{
    GtkWidget *window;
    GtkWidget *image;
    GtkWidget *file_button;
    GtkWidget *crack_button;
    GtkWidget *fixed;
    const char* patch_filename;
    AudioData* audio;
};

// Creating window and background ---------------------------------------------------
GtkWidget *create_window(const char* name);
GtkWidget *create_background(const char* name, GtkWidget* fixed);

// Creating and processing crack/patch button ---------------------------------------
GtkWidget *make_crack_button(Widgets *widgets);
static void process_patch_button(GtkFileChooserButton *button, gpointer user_data);
static bool is_patch_correct(Widgets *widgets);
static void show_patch_result(const char* name, Widgets *widgets);
static gboolean destroy_picture(gpointer user_data);
static void set_music(Widgets *widgets, ma_sound* sound, bool* is_init, const char* path);

// Creating and processing file button ---------------------------------------
GtkWidget *make_file_button(Widgets *widgets);
static void process_file_button(GtkFileChooserButton *button, gpointer user_data);


int main(int argc, char *argv[]) {
    // Audio init ------------------------------------------------------------
    AudioData *audio = (AudioData*)calloc(sizeof(AudioData), 1);
    ma_engine engine = {};

    ma_result result = ma_engine_init(NULL, &engine);
    if (result != MA_SUCCESS) {
        return result;  
    }
    audio->engine = engine;

    ma_sound_init_from_file(&(audio->engine), "CRACK/CR_PROG/ADDIT/wait.mp3", MA_SOUND_FLAG_LOOPING, NULL, NULL, &(audio->sound_wait));
    ma_sound_start(&(audio->sound_wait));

    audio->success_init = false;
    audio->fail_init = false;

    // Graphic init ------------------------------------------------------------
    gtk_init(&argc, &argv);

    Widgets *widgets = g_new(Widgets, 1);
    widgets->patch_filename = NULL;
    widgets->audio = audio;
 
    widgets->window = create_window("CRACKme patcher");

    widgets->fixed = gtk_fixed_new();
    gtk_container_add(GTK_CONTAINER(widgets->window), widgets->fixed);

    widgets->image = create_background("CRACK/CR_PROG/ADDIT/image.png", widgets->fixed);

    widgets->crack_button = make_crack_button(widgets);
    widgets->file_button = make_file_button(widgets);

    gtk_widget_show_all(widgets->window);

    gtk_main();

    // Destroy ------------------------------------------------------------
    if(widgets->audio){
        if(widgets->audio->fail_init){
            ma_sound_uninit(&widgets->audio->sound_fail);
        }
        if(widgets->audio->success_init){
            ma_sound_uninit(&widgets->audio->sound_success);
        }
        ma_sound_uninit(&widgets->audio->sound_wait);
        ma_engine_uninit(&widgets->audio->engine);
        free(widgets->audio);
    }

    if(widgets->patch_filename){
        free((char*)widgets->patch_filename);
        widgets->patch_filename = NULL;
    }
    g_free(widgets);
    
    return 0;
}

//-------------------------------------------------------------------------------------------------
// Create music



//--------------------------------------------------------------------------------------------------
// Making window, background

GtkWidget *create_window(const char* name){

    GtkWidget *window = gtk_window_new(GTK_WINDOW_TOPLEVEL);
    gtk_window_set_title(GTK_WINDOW(window), name);

    gtk_window_set_default_size(GTK_WINDOW(window), WINDOW_WIDTH, WINDOW_HEIGHT);
    gtk_window_set_position(GTK_WINDOW(window), GTK_WIN_POS_CENTER);

    g_signal_connect(window, "destroy", G_CALLBACK(gtk_main_quit), NULL);

    return window;
}

GtkWidget *create_background(const char* name, GtkWidget* fixed){

    GdkPixbuf *original = gdk_pixbuf_new_from_file(name, NULL);
    GdkPixbuf *scaled = gdk_pixbuf_scale_simple(original, WINDOW_WIDTH, WINDOW_HEIGHT, GDK_INTERP_BILINEAR);

    GtkWidget *image = gtk_image_new_from_pixbuf(scaled);

    g_object_unref(original);
    g_object_unref(scaled);

    gtk_fixed_put(GTK_FIXED(fixed), image, 0, 0);

    return image;
}

//-------------------------------------------------------------------------------------------------
// Making and processing file crack button

GtkWidget *make_crack_button(Widgets *widgets){

    GtkWidget *crack_button = gtk_button_new();
    gtk_widget_set_size_request(crack_button, CRACK_BUTTON_WIDTH, CRACK_BUTTON_HEIGHT);

    gtk_widget_set_opacity(crack_button, 0.0);

    g_signal_connect(crack_button, "clicked", G_CALLBACK(process_patch_button), widgets);
    gtk_fixed_put(GTK_FIXED(widgets->fixed), crack_button, CRACK_BUTTON_X, CRACK_BUTTON_Y);

    return crack_button;
}

// Patch processing --------------------------------------------------------------------------------

static void process_patch_button(GtkFileChooserButton *button, gpointer user_data){
    Widgets *widgets = (Widgets*)user_data;

    if(widgets->image)        gtk_widget_hide(widgets->image);
    if(widgets->file_button)  gtk_widget_hide(widgets->file_button);
    if(widgets->crack_button) gtk_widget_hide(widgets->crack_button);
    
    if(!(is_patch_correct(widgets))){
        show_patch_result("CRACK/CR_PROG/ADDIT/fail.png", widgets);
        set_music(widgets, &(widgets->audio->sound_fail), &(widgets->audio->fail_init), "CRACK/CR_PROG/ADDIT/fail.mp3");
        return;
    }
    show_patch_result("CRACK/CR_PROG/ADDIT/success.png", widgets);
    set_music(widgets, &(widgets->audio->sound_success), &(widgets->audio->success_init), "CRACK/CR_PROG/ADDIT/success.mp3");

}

static bool is_patch_correct(Widgets *widgets){
    FILE *file = fopen(widgets->patch_filename, "rb+");
    if(!file){
        fprintf(stderr, "Incorrect file - can't open");
        return false;
    }

    int sum_real = 0;
    char byte = fgetc(file);
    while (byte != EOF) {
        sum_real += (unsigned char)byte; 
        byte = fgetc(file);
    }

    if(sum_real != SUM){
        fprintf(stderr, "Incorrect file - hash doesn't match");
        return false;
    }

    fseek(file, 0x78 ,SEEK_SET);  
    
    unsigned char new_byte = 0xEB;
    fwrite(&new_byte, 1, 1, file);

    fclose(file);
    return true;
}

static void show_patch_result(const char* name, Widgets *widgets){
    if(!name) return;

    GtkWidget *result_image = create_background(name, widgets->fixed);
    gtk_widget_show(result_image);
    g_timeout_add(10000, destroy_picture, result_image);

    gtk_widget_show(widgets->image);
    gtk_widget_show(widgets->file_button);
    gtk_widget_show(widgets->crack_button);
}

static gboolean destroy_picture(gpointer user_data){
    GtkWidget* picture = (GtkWidget*)user_data;
    if(picture) gtk_widget_destroy(picture);   
    return FALSE;  
}

static void set_music(Widgets *widgets, ma_sound* sound, bool* is_init, const char* path){
    if(!path || !sound || !is_init) return;

    ma_sound_stop(&(widgets->audio->sound_wait));  
    if(!(*is_init)){
        ma_sound_init_from_file(&(widgets->audio->engine), path, 0, NULL, NULL, sound);
        *is_init = true;
    }  
    ma_sound_start(sound);
    while(ma_sound_is_playing(sound)){
        gtk_main_iteration_do(FALSE); 
    }
    ma_sound_start(&(widgets->audio->sound_wait));
}

//-------------------------------------------------------------------------------------------------
// Making and processing file choosing button

GtkWidget *make_file_button(Widgets *widgets){

    GtkWidget *file_button = gtk_file_chooser_button_new("Choose you file", GTK_FILE_CHOOSER_ACTION_OPEN);
    gtk_widget_set_size_request(file_button, FILE_BUTTON_WIDTH, FILE_BUTTON_HEIGHT);

    gtk_widget_set_opacity(file_button, 0.0);

    g_signal_connect(file_button, "file-set", G_CALLBACK(process_file_button), widgets);
    gtk_fixed_put(GTK_FIXED(widgets->fixed), file_button, FILE_BUTTON_X, FILE_BUTTON_Y);

    return file_button;
}

// File button processing ---------------------------------------------------------------------------

static void process_file_button(GtkFileChooserButton *button, gpointer user_data){
    Widgets *widgets = (Widgets*)user_data;

    char *filename = gtk_file_chooser_get_filename(GTK_FILE_CHOOSER(button));

    if(filename){
        g_print("File, that was chosen: %s\n", filename);

        widgets->patch_filename = g_strdup(filename);
        g_free(filename);
    }
}

