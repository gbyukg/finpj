import org.boon.Boon;
import groovy.io.FileType

def base_db_img_list = []
def base_db_imgs = ''
def dir = new File("/gsa/pokgsa/projects/s/salesconnectcn/db2backup")
dir.eachFileRecurse (FileType.FILES) { file ->
    base_db_img_list << file.getName()
}

base_db_imgs = base_db_img_list.join(", ")

def jsonEditorOptions = Boon.fromJson(/{
        disable_edit_json: true,
        disable_properties: true,
        disable_collapse: true,
        disable_array_add: true,
        disable_array_delete: true,
        disable_array_reorder: true,
        input_height: "60px",
        theme: "bootstrap2",
        iconlib:"fontawesome4",
        schema: {
            type: "object",
            title: "",
            properties: {
                source_from: {
                    title: "Chose SC source",
                    type: "array",
                    format: "tabs",
                    propertyOrder : 1,
                    items: {
                        title: "source",
                        headerTemplate: "{{self.name}}",
                        type: "object",
                        properties: {
                            name : {
                                type: "string",
                                title: "",
                                readOnly: "true",
                            },
                            git : {
                                title: "GIT PRs or branches",
                                type: "string",
                                format: "textarea",
                                description: "\nYou can provide one or more RP numbers to install a new SC base on some particular PRs\n, or provide one or more Git branchs.\n PR number and Git branch can be used together.\n For example: 1234\nsugareps:ibm_r40\nzzlzhang:ibms_1234",
                                input_height: "60px",
                            },
                            package : {
                                title: "Install & upgrade packages",
                                type: "string",
                                format: "textarea",
                            }
                        }
                    }
                },
                install_method: {
                    title: "Chose install method",
                    type: "array",
                    format: "tabs",
                    propertyOrder : 2,
                    items: {
                        title: "",
                        headerTemplate: "{{self.name}}",
                        type: "object",
                        properties: {
                            name : {
                                type: "string",
                                title: "",
                                hidden: "true",
                                hiddenTitle: "true",
                                readOnly: "true",
                            },
                            base_db : {
                                title: "Base DB",
                                description: "\nChoice which DB you want to use as a base DB, the process will create A new SC Instance base on your choice.",
                                type: "string",
                                enum: [' ', ${base_db_imgs}],
                                propertyOrder : 1,
                            },
                            run_dataloader: {
                                type: "boolean",
                                format: "checkbox",
                                title: "Import dataloader",
                                propertyOrder : 2,
                            },
                            run_avl: {
                                type: "boolean",
                                format: "checkbox",
                                title: "Import AVLs",
                                propertyOrder : 3,
                            },
                            run_unit: {
                                type: "boolean",
                                format: "checkbox",
                                title: "Run PHP UT",
                                propertyOrder : 4,
                            },
                            as_base_db: {
                                type: "boolean",
                                format: "checkbox",
                                title: "As base DB img",
                                propertyOrder : 5,
                            },
                        }
                    }
                },
                keep_live : {
                    type: "string",
                    format: "number",
                    title: "How log you want to keep the instance",
                    description: "1 ~ 30",
                    propertyOrder : 3
                },
                install_bp: {
                    type: "boolean",
                    format: "checkbox",
                    title: "Install SC4BP instance",
                    propertyOrder : 4
                },
                independent_es: {
                    type: "boolean",
                    format: "checkbox",
                    title: 'Create a independent ES',
                    propertyOrder : 5
                },
                run_qrr: {
                    type: "boolean",
                    format: "checkbox",
                    title: 'Run QRR after installation',
                    propertyOrder : 6
                },
                instance_name: {
                    type: "string",
                    title: "Instance Name",
                    propertyOrder : 7
                },
                db_name: {
                    type: "string",
                    title: "Instance DB Name",
                    propertyOrder : 8
                },
                atoi_install_hook: {
                    type: "string",
                    title: "Custom instance Hooks",
                    propertyOrder : 9
                },
            }
        },

        startval: {
            keep_live: 3,
            install_bp : 0,
            independent_es : 0,
            instance_name : '',
            db_name : "",
            run_qrr : '',
            atoi_install_hook : '',
            source_from : [
                {
                    name: 'git',
                    git: ''
                },
                {
                    name: 'package',
                    package: ''
                }
            ],
            install_method: [
                {
                    name: 'RESTORE',
                    base_db: '',
                    run_dataloader: '',
                    run_avl: '',
                    run_unit: 1,
                },
                {
                    name: 'FULL_INSTALL',
                    run_dataloader: 1,
                    run_avl: 1,
                    run_unit: 1,
                    as_base_db: 0,
                }
            ],
        }
}/);
